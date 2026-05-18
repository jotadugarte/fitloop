# frozen_string_literal: true

module Nesting
  # Marks a processing nesting run and project as failed (idempotent).
  class FailRun
    def self.call(nesting_run:, error: nil, message: nil)
      new(nesting_run: nesting_run, error: error, message: message).call
    end

    def initialize(nesting_run:, error: nil, message: nil)
      @nesting_run = nesting_run
      @project = nesting_run.project
      @error = error
      @message = message
    end

    def call
      return false unless @nesting_run.status == "processing"
      return false unless @project

      progress_message = @message || failure_message(@error)

      @nesting_run.update!(
        status: "failed",
        finished_at: Time.current,
        report_json: failure_report(@error)
      )
      @project.update!(
        status: :failed,
        progress_percent: 0,
        progress_message: progress_message
      )
      ProgressBroadcaster.call(project: @project.reload, eta_overrun: false, time_limit_notice: false)
      true
    end

    private

    def failure_message(error)
      return I18n.t("nesting.input_file_missing") if error.is_a?(ActiveStorage::FileNotFoundError)

      I18n.t("nesting.failed")
    end

    def failure_report(error)
      warnings = []
      warnings << "input_file_missing" if error.is_a?(ActiveStorage::FileNotFoundError)
      warnings << error.message if error.present?

      { "status" => "failed", "warnings" => warnings.compact.uniq }
    end
  end
end
