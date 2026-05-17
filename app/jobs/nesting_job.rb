# frozen_string_literal: true

# [REQ-FIT-CLI-001] Solid Queue job that runs nesting_engine via Nesting::CliRunner.
class NestingJob < ApplicationJob
  queue_as :default

  def perform(nesting_run_id)
    nesting_run = NestingRun.find(nesting_run_id)
    project = nesting_run.project
    nesting_run.update!(status: "processing", started_at: Time.current)
    project.update!(progress_percent: 8, progress_message: I18n.t("nesting.preparing"))
    Nesting::ProgressBroadcaster.call(project: project.reload, eta_overrun: false, time_limit_notice: false)

    Nesting::JobRunner.call(nesting_run: nesting_run)
  end
end
