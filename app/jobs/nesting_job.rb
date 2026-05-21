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
    project.update!(progress_percent: 8, progress_message: I18n.t("nesting.phase.preparing"))
    Nesting::ProgressBroadcaster.call(project: project.reload, eta_overrun: false, time_limit_notice: false)

    Nesting::JobRunner.call(nesting_run: nesting_run)
  rescue StandardError => error
    nesting_run = NestingRun.find_by(id: nesting_run_id)
    Nesting::FailRun.call(nesting_run: nesting_run, error: error) if nesting_run&.status == "processing"
  end
end
