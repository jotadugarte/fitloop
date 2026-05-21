# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-003] Maps CLI exit code and report.json to terminal job status.
  class StatusMapper
    TERMINAL_STATUSES = %w[completed partial failed].freeze
    # Runs that may attach nested.dxf and authorize paywall/download (D23, REQ-FIT-NEST-003).
    DOWNLOADABLE_RUN_STATUSES = %w[completed partial].freeze

    def self.map(exit_status:, report:, work_dir:)
      new(exit_status: exit_status, report: report, work_dir: work_dir).map
    end

    def self.attach_nested_output?(terminal_status:, work_dir:)
      return false unless TERMINAL_STATUSES.include?(terminal_status)
      return false if terminal_status == "failed"

      Pathname(work_dir).join("output", "nested.dxf").file?
    end

    def initialize(exit_status:, report:, work_dir:)
      @exit_status = exit_status
      @report = report || {}
      @work_dir = Pathname(work_dir)
    end

    def map
      return map_nonzero_exit unless @exit_status.zero?

      normalize_report_status(@report["status"])
    end

    private

    def map_nonzero_exit
      return "partial" if partial_artifacts_present?

      "failed"
    end

    def partial_artifacts_present?
      report_path = @work_dir.join("output", "report.json")
      nested_path = @work_dir.join("output", "nested.dxf")
      return false unless report_path.file? && nested_path.file?

      report = JSON.parse(report_path.read)
      %w[partial completed].include?(report["status"].to_s)
    rescue JSON::ParserError
      false
    end

    def normalize_report_status(report_status)
      status = report_status.to_s
      return status if TERMINAL_STATUSES.include?(status)

      "failed"
    end
  end
end
