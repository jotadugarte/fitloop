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
    last_event = UserEvent.where(project_id: project.id).order(occurred_at: :desc).first

    Analytics::TrackEvent.call(
      "nest_completed",
      user_id: last_event&.user_id,
      anonymous_session_key: last_event&.anonymous_session_key,
      tab_id: last_event&.tab_id,
      project_id: project.id,
      nesting_run_id: nesting_run.id,
      ip: last_event&.ip,
      user_agent: last_event&.user_agent,
      country_code: last_event&.country_code,
      locale: last_event&.locale || I18n.default_locale.to_s,
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
    placements = parse_placements(nesting_run)
    placements&.dig("sheets")&.size || 0
  end

  def parse_pieces_count(nesting_run)
    placements = parse_placements(nesting_run)
    placements&.dig("sheets")&.sum { |s| s["pieces"]&.size || 0 } || 0
  end

  def parse_orphans_by_reason(nesting_run)
    orphans = (nesting_run.report_json || {})["orphans"] || []
    return {} unless orphans.any?

    orphans.group_by { |o| o["reason"] }.transform_values(&:size)
  end
end
