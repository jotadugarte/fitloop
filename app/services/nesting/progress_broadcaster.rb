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
      broadcast_progress!
      return if @project.processing?

      broadcast_show_actions!
      broadcast_nesting_preview!
    end

    private

    def broadcast_progress!
      @project.broadcast_replace_to(
        @project,
        target: ActionView::RecordIdentifier.dom_id(@project, :nesting_progress),
        partial: "projects/nesting_progress",
        locals: {
          project: @project,
          orphans: OrphansPresenter.for(@project),
          eta_overrun: @eta_overrun,
          time_limit_notice: @time_limit_notice
        }
      )
    end

    def broadcast_show_actions!
      @project.broadcast_replace_to(
        @project,
        target: ActionView::RecordIdentifier.dom_id(@project, :show_actions),
        partial: "projects/show_actions",
        locals: { project: @project }
      )
    end

    def broadcast_nesting_preview!
      preview = PreviewPresenter.for(@project)
      @project.broadcast_replace_to(
        @project,
        target: ActionView::RecordIdentifier.dom_id(@project, :nesting_preview),
        partial: "projects/nesting_preview",
        locals: { project: @project, preview: preview }
      )
    end
  end
end
