# frozen_string_literal: true

module Nesting
  # Reconcile project.status with the latest nesting run when Turbo missed broadcasts.
  class ProjectStatusSync
    TERMINAL_STATUSES = StatusMapper::TERMINAL_STATUSES

    def self.call(project:)
      new(project: project).call
    end

    def initialize(project:)
      @project = project
    end

    def call
      return @project.reload unless @project.processing?

      run = latest_run
      return @project.reload if run.nil?

      reconcile_stale_processing_run!(run) if run.status == "processing"
      sync_project_from_run!(run.reload) if run.reload.status != "processing"

      @project.reload
    end

    private

    def latest_run
      @project.nesting_runs.order(created_at: :desc).first
    end

    def reconcile_stale_processing_run!(run)
      return if CliRunner.finalize_from_work_dir!(nesting_run: run)
      return unless stale_processing_run?(run)

      terminal_status = infer_terminal_status(run)
      return unless terminal_status

      run.update!(
        status: terminal_status,
        finished_at: Time.current,
        report_json: terminal_report(run) || { "status" => terminal_status }
      )
    end

    def stale_processing_run?(run)
      return true if @project.placements_json.attached?
      return true if terminal_report(run).present?

      false
    end

    def terminal_report(run)
      report = load_work_dir_report(run)
      return nil if report.empty?

      status = report["status"].to_s
      TERMINAL_STATUSES.include?(status) ? report : nil
    end

    def infer_terminal_status(run)
      report = terminal_report(run)
      return report["status"].to_s if report

      return "completed" if @project.placements_json.attached?

      nil
    end

    def load_work_dir_report(run)
      work_dir = Pathname(Rails.root.join("tmp/nesting_runs", run.id.to_s))
      report_path = work_dir.join("output", "report.json")
      return {} unless report_path.file?

      JSON.parse(report_path.read)
    rescue JSON::ParserError
      {}
    end

    def sync_project_from_run!(run)
      @project.update!(
        status: run.status,
        progress_percent: 100,
        progress_message: terminal_progress_message(run.status)
      )
    end

    def terminal_progress_message(status)
      case status
      when "completed" then I18n.t("nesting.completed")
      when "partial" then I18n.t("nesting.partial")
      else I18n.t("nesting.failed")
      end
    end
  end
end
