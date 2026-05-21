# frozen_string_literal: true

module Nesting
  # [REQ-FIT-SPLIT-001] Refreshes orphan cards and nesting actions after split workflow changes.
  class SplitWorkflowBroadcaster
    def self.call(project:)
      new(project: project).call
    end

    def initialize(project:)
      @project = project
    end

    def call
      orphans = OrphansPresenter.for(@project)
      broadcast_orphans!(orphans)
      broadcast_show_actions!
    end

    private

    def broadcast_orphans!(orphans)
      @project.broadcast_replace_to(
        @project,
        target: ActionView::RecordIdentifier.dom_id(@project, :nesting_orphans),
        partial: "projects/nesting_orphans_frame",
        locals: { project: @project, orphans: orphans }
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
  end
end
