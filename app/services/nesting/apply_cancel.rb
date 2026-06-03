# frozen_string_literal: true

module Nesting
  # [REQ-FIT-JOB-001] Marks a processing nesting run and project as cancelled (idempotent).
  class ApplyCancel
    def self.call(nesting_run:)
      new(nesting_run: nesting_run).call
    end

    def initialize(nesting_run:)
      @nesting_run = nesting_run
      @project = nesting_run.project
    end

    def call
      return false unless @nesting_run.cancel_requested_at.present?
      return false unless @nesting_run.status == "processing"

      @nesting_run.update!(
        status: "failed",
        finished_at: Time.current,
        report_json: { "status" => "failed", "warnings" => [ "cancelled" ] }
      )
      @project.update!(
        status: :failed,
        progress_percent: 0,
        progress_message: "nesting.cancelled"
      )
      ProgressBroadcaster.call(project: @project.reload, eta_overrun: false, time_limit_notice: false)
      invalidate_split_previews!
      true
    end

    def invalidate_split_previews!
      SheetStocks::InvalidateSplitPreviews.call(@project)
    end
  end
end
