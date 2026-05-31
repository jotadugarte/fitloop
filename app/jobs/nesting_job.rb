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
        report_json: { "status" => "failed", "warnings" => ["project_missing"] }
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
      if nesting_run && nesting_run.status != "processing"
        last_event = UserEvent.where(project_id: project.id).order(occurred_at: :desc).first

        sheets_used = 0
        pieces_count = 0
        orphans_by_reason = {}

        work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s)
        placements_path = work_dir.join("output", "placements.json")
        if placements_path.file?
          begin
            placements = JSON.parse(placements_path.read)
            sheets_used = placements["sheets"]&.size || 0
            pieces_count = placements["sheets"]&.sum { |s| s["pieces"]&.size || 0 } || 0
          rescue => e
            Rails.logger.error("[NestingJob telemetry] Failed to parse placements: #{e.message}")
          end
        end

        report = nesting_run.report_json || {}
        orphans = report["orphans"] || []
        if orphans.any?
          orphans_by_reason = orphans.group_by { |o| o["reason"] }.transform_values(&:size)
        end

        duration_ms = 0
        started = nesting_run.started_at
        finished = nesting_run.finished_at || Time.current
        if started
          duration_ms = ((finished - started) * 1000).to_i
        end

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
          locale: last_event&.locale || "es",
          properties: {
            duration_ms: duration_ms,
            sheets_used: sheets_used,
            pieces_count: pieces_count,
            orphans_by_reason: orphans_by_reason,
            status: nesting_run.status
          }
        )
      end
    end
  end
end
