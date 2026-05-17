# frozen_string_literal: true

module Nesting
  # [REQ-FIT-JOB-001] Turbo Stream updates for nesting progress on the project page.
  class ProgressBroadcaster
    def self.call(project:, eta_overrun: false, time_limit_notice: false)
      new(project: project, eta_overrun: eta_overrun, time_limit_notice: time_limit_notice).call
    end

    def initialize(project:, eta_overrun:, time_limit_notice:)
      @project = project
      @eta_overrun = eta_overrun
      @time_limit_notice = time_limit_notice
    end

    def call
      @project.broadcast_replace_to(
        @project,
        target: ActionView::RecordIdentifier.dom_id(@project, :nesting_progress),
        partial: "projects/nesting_progress",
        locals: {
          project: @project,
          eta_overrun: @eta_overrun,
          time_limit_notice: @time_limit_notice
        }
      )
    end
  end
end
