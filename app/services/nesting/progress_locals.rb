# frozen_string_literal: true

module Nesting
  # [REQ-FIT-JOB-001] Shared locals for nesting_progress partial (show, sync, broadcaster).
  module ProgressLocals
    module_function

    def for(project, time_limit_notice: false)
      {
        project: project,
        active_run: active_processing_run(project),
        eta_overrun: eta_overrun?(project),
        time_limit_notice: time_limit_notice,
        time_remaining: TimeRemainingMessage.for(project)
      }
    end

    def active_processing_run(project)
      project.nesting_runs.order(created_at: :desc).find_by(status: "processing")
    end

    def eta_overrun?(project)
      project.estimated_finished_at.present? && Time.current > project.estimated_finished_at
    end
  end
end
