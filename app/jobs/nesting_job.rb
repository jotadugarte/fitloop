# frozen_string_literal: true

# [REQ-FIT-CLI-001] Solid Queue job that runs nesting_engine via Nesting::CliRunner.
class NestingJob < ApplicationJob
  queue_as :default

  def perform(nesting_run_id)
    nesting_run = NestingRun.find(nesting_run_id)
    nesting_run.project.update!(status: :processing)
    nesting_run.update!(status: "processing", started_at: Time.current)

    Nesting::CliRunner.call(nesting_run: nesting_run)
  end
end
