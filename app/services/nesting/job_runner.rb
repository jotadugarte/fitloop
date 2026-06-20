# frozen_string_literal: true

require "timeout"
require "fileutils"

module Nesting
  # [REQ-FIT-JOB-001] Orchestrates nesting with progress, cancel, and time limit.
  class JobRunner
    # Throttle cancel DB polls during CLI nesting; cancel may take up to this long to observe.
    CANCEL_CACHE_TTL_SEC = 0.5

    def self.call(nesting_run:)
      new(nesting_run: nesting_run).call
    end

    def initialize(nesting_run:)
      raise ArgumentError, "nesting_run must be present" if nesting_run.nil?
      @nesting_run = nesting_run
      @project = nesting_run.project
      @cancel_requested_at = nesting_run.cancel_requested_at
      @cancel_cache_checked_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def call
      time_limit = NestingTimeLimitSec.from_project(@project)

      return if handle_cancelled!

      update_progress!(percent: 12, message: I18n.t("nesting.phase.starting"))

      work_dir = Rails.root.join("tmp/nesting_runs", @nesting_run.id.to_s)
      begin
        begin
          Timeout.timeout(time_limit.to_i) do
            raise CancelledError if cancel_requested?

            Nesting::CliRunner.call(
              nesting_run: @nesting_run,
              cancel_check: -> { cancel_requested? }
            )
          end
        rescue Timeout::Error
          handle_timeout!
        rescue CancelledError
          handle_cancelled!
        rescue StandardError => error
          handle_failure!(error)
        else
          return if handle_cancelled!

          update_progress!(percent: 100, message: terminal_progress_message)
          ProgressBroadcaster.call(
            project: @project.reload,
            eta_overrun: eta_overrun?,
            time_limit_notice: false
          )
        end
      ensure
        FileUtils.rm_rf(work_dir)
        # Post-condition: workspace directory must be deleted
        raise "Post-condition violation: workspace directory still exists" if File.exist?(work_dir)
      end
    end

    private

    def cancel_requested?
      refresh_cancel_cache_if_stale!
      @cancel_requested_at.present?
    end

    def handle_cancelled!
      return false unless cancel_requested?

      ApplyCancel.call(nesting_run: @nesting_run)
      true
    end

    def handle_failure!(error)
      Rails.logger.error("[Nesting::JobRunner] nesting_run=#{@nesting_run.id} #{error.class}: #{error.message}")
      Rails.logger.error(error.backtrace&.first(8)&.join("\n"))

      FailRun.call(nesting_run: @nesting_run, error: error)
    end

    def handle_timeout!
      work_dir = Rails.root.join("tmp/nesting_runs", @nesting_run.id.to_s)
      report = load_report(work_dir).merge(
        "status" => "partial",
        "warnings" => Array(report_warnings(work_dir)) + [ "time_limit_reached" ]
      )
      terminal_status = "partial"
      attach_outputs_if_present!(work_dir, terminal_status)

      @nesting_run.update!(status: terminal_status, report_json: report, finished_at: Time.current)
      @project.update!(
        status: terminal_status,
        progress_percent: 100,
        progress_message: "nesting.time_limit_notice"
      )
      ProgressBroadcaster.call(
        project: @project,
        eta_overrun: eta_overrun?,
        time_limit_notice: true
      )
    end

    def attach_outputs_if_present!(work_dir, terminal_status)
      return unless %w[completed partial].include?(terminal_status)

      nested_path = Pathname(work_dir).join("output", "nested.dxf")
      if nested_path.file? && StatusMapper.attach_nested_output?(terminal_status: terminal_status, work_dir: work_dir)
        File.open(nested_path) do |file|
          @project.nested_dxf.attach(
            io: file,
            filename: "nested.dxf",
            content_type: "application/dxf"
          )
        end
      end

      placements_path = Pathname(work_dir).join("output", "placements.json")
      return unless placements_path.file?

      File.open(placements_path) do |file|
        @project.placements_json.attach(
          io: file,
          filename: "placements.json",
          content_type: "application/json"
        )
      end
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

    def refresh_cancel_cache_if_stale!
      now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      return if now - @cancel_cache_checked_at < CANCEL_CACHE_TTL_SEC

      @cancel_requested_at = NestingRun.uncached do
        NestingRun.where(id: @nesting_run.id).pick(:cancel_requested_at)
      end
      @cancel_cache_checked_at = now
    end

    def terminal_progress_message
      case @project.reload.status
      when "completed" then "nesting.completed"
      when "partial" then "nesting.partial"
      else "nesting.failed"
      end
    end
  end
end
