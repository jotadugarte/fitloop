# frozen_string_literal: true

# [REQ-FIT-CLI-001] Solid Queue job that runs nesting_engine via Nesting::CliRunner.
class NestingJob < ApplicationJob
  queue_as :default

  def perform(nesting_run_id)
    nesting_run = NestingRun.find_by(id: nesting_run_id)
    return unless nesting_run

    project = nesting_run.project
    unless project
      nesting_run.update!(
        status: "failed",
        finished_at: Time.current,
        report_json: { "status" => "failed", "warnings" => [ "project_missing" ] }
      )
      return
    end

    nesting_run.update!(status: "processing", started_at: Time.current)
    project.update!(progress_percent: 8, progress_message: "nesting.phase.preparing")
    Nesting::ProgressBroadcaster.call(project: project.reload, eta_overrun: false, time_limit_notice: false)

    begin
      Nesting::JobRunner.call(nesting_run: nesting_run)
    rescue StandardError => error
      nesting_run = NestingRun.find_by(id: nesting_run_id)
      Nesting::FailRun.call(nesting_run: nesting_run, error: error) if nesting_run&.status == "processing"
    ensure
      nesting_run = NestingRun.find_by(id: nesting_run_id)
      emit_nest_telemetry(nesting_run, project) if nesting_run && nesting_run.status != "processing"
    end
  end

  private

  def emit_nest_telemetry(nesting_run, project)
    context = Analytics::NestTelemetryContext.from(project: project, nesting_run: nesting_run)

    Analytics::TrackEvent.call(
      "nest_completed",
      user_id: context.user_id,
      anonymous_session_key: context.anonymous_session_key,
      tab_id: context.tab_id,
      project_id: project.id,
      nesting_run_id: nesting_run.id,
      ip: context.ip,
      user_agent: context.user_agent,
      country_code: context.country_code,
      locale: context.locale,
      properties: nest_telemetry_properties(nesting_run)
    )
  end

  def nest_telemetry_properties(nesting_run)
    {
      duration_ms: compute_duration_ms(nesting_run),
      sheets_used: parse_sheets_used(nesting_run),
      pieces_count: parse_pieces_count(nesting_run),
      orphans_by_reason: parse_orphans_by_reason(nesting_run),
      status: nesting_run.status
    }
  end

  def compute_duration_ms(nesting_run)
    started = nesting_run.started_at
    return 0 unless started

    finished = nesting_run.finished_at || Time.current
    ((finished - started) * 1000).to_i
  end

  def parse_placements(nesting_run)
    path = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output", "placements.json")
    return nil unless path.file?

    JSON.parse(path.read)
  rescue StandardError => e
    Rails.logger.error("[NestingJob telemetry] Failed to parse placements: #{e.message}")
    nil
  end

  def parse_sheets_used(nesting_run)
    if nesting_run.report_json.is_a?(Hash) && nesting_run.report_json.key?("sheets_used")
      return nesting_run.report_json["sheets_used"].to_i
    end

    placements = parse_placements(nesting_run)
    placements&.dig("sheets")&.size || 0
  end

  def parse_pieces_count(nesting_run)
    if nesting_run.report_json.is_a?(Hash) && nesting_run.report_json.key?("pieces_count")
      return nesting_run.report_json["pieces_count"].to_i
    end

    placements = parse_placements(nesting_run)
    placements&.dig("sheets")&.sum { |s| s["pieces"]&.size || 0 } || 0
  end

  def parse_orphans_by_reason(nesting_run)
    orphans = (nesting_run.report_json || {})["orphans"] || []
    return {} unless orphans.any?

    orphans.group_by { |o| o["reason"] }.transform_values(&:size)
  end
end
