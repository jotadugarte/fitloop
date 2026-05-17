# frozen_string_literal: true

module Nesting
  # Reconcile project.status with the latest nesting run when Turbo missed broadcasts.
  class ProjectStatusSync
    def self.call(project:)
      new(project: project).call
    end

    def initialize(project:)
      @project = project
    end

    def call
      return @project unless @project.processing?

      run = @project.nesting_runs.order(created_at: :desc).first
      return @project if run.nil? || run.status == "processing"

      @project.update!(
        status: run.status,
        progress_percent: 100,
        progress_message: terminal_progress_message(run.status)
      )
      @project
    end

    private

    def terminal_progress_message(status)
      case status
      when "completed" then I18n.t("nesting.completed")
      when "partial" then I18n.t("nesting.partial")
      else I18n.t("nesting.failed")
      end
    end
  end
end
