# frozen_string_literal: true

require "timeout"

module Nesting
  # [REQ-FIT-JOB-001] Orchestrates nesting with progress, cancel, and time limit.
  class JobRunner
    def self.call(nesting_run:)
      new(nesting_run: nesting_run).call
    end

    def initialize(nesting_run:)
      @nesting_run = nesting_run
      @project = nesting_run.project
    end

    def call
      return if handle_cancelled!

      update_progress!(percent: 5, message: I18n.t("nesting.preparing"))
      update_progress!(percent: 15, message: I18n.t("nesting.running"))

      begin
        Timeout.timeout(@project.nesting_time_limit_sec) do
          raise CancelledError if cancelled?

          Nesting::CliRunner.call(
            nesting_run: @nesting_run,
            cancel_check: -> { cancelled? }
          )
        end
      rescue Timeout::Error
        handle_timeout!
      rescue CancelledError
        handle_cancelled!
      else
        update_progress!(percent: 100, message: terminal_progress_message)
        ProgressBroadcaster.call(
          project: @project.reload,
          eta_overrun: eta_overrun?,
          time_limit_notice: false
        )
      end
    end

    private

    def cancelled?
      @nesting_run.reload.cancel_requested_at.present?
    end

    def handle_cancelled!
      return false unless cancelled?

      @nesting_run.update!(
        status: "failed",
        finished_at: Time.current,
        report_json: { "status" => "failed", "warnings" => ["cancelled"] }
      )
      @project.update!(
        status: :failed,
        progress_percent: 0,
        progress_message: I18n.t("nesting.cancelled")
      )
      ProgressBroadcaster.call(project: @project, eta_overrun: false, time_limit_notice: false)
      true
    end

    def handle_timeout!
      work_dir = Rails.root.join("tmp/nesting_runs", @nesting_run.id.to_s)
      report = load_report(work_dir).merge(
        "status" => "partial",
        "warnings" => Array(report_warnings(work_dir)) + ["time_limit_reached"]
      )
      terminal_status = StatusMapper.map(exit_status: 1, report: report, work_dir: work_dir)
      attach_nested_if_present!(work_dir, terminal_status)

      @nesting_run.update!(status: terminal_status, report_json: report, finished_at: Time.current)
      @project.update!(
        status: terminal_status,
        progress_percent: 100,
        progress_message: I18n.t("nesting.time_limit_notice")
      )
      ProgressBroadcaster.call(
        project: @project,
        eta_overrun: eta_overrun?,
        time_limit_notice: true
      )
    end

    def attach_nested_if_present!(work_dir, terminal_status)
      return unless StatusMapper.attach_nested_output?(terminal_status: terminal_status, work_dir: work_dir)

      nested_path = Pathname(work_dir).join("output", "nested.dxf")
      @project.nested_dxf.attach(
        io: File.open(nested_path),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
    end

    def load_report(work_dir)
      report_path = Pathname(work_dir).join("output", "report.json")
      return {} unless report_path.file?

      JSON.parse(report_path.read)
    rescue JSON::ParserError
      {}
    end

    def report_warnings(work_dir)
      load_report(work_dir).fetch("warnings", [])
    end

    def update_progress!(percent:, message:)
      @project.update!(progress_percent: percent, progress_message: message)
      ProgressBroadcaster.call(
        project: @project,
        eta_overrun: eta_overrun?,
        time_limit_notice: false
      )
    end

    def eta_overrun?
      @project.estimated_finished_at.present? && Time.current > @project.estimated_finished_at
    end

    def terminal_progress_message
      case @project.reload.status
      when "completed" then I18n.t("nesting.completed")
      when "partial" then I18n.t("nesting.partial")
      else I18n.t("nesting.failed")
      end
    end
  end
end
