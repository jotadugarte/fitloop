# frozen_string_literal: true

module Nesting
  # [REQ-FIT-SPLIT-001] Runs split plan CLI and stores a draft SplitProposal for preview.
  class SplitPlanJob < ApplicationJob
    queue_as :nesting

    def perform(orphan_resolution_id)
      orphan_resolution = OrphanResolution.find_by(id: orphan_resolution_id)
      return unless orphan_resolution

      payload = SplitPlannerRunner.call(orphan_resolution: orphan_resolution)
      persist_draft_proposal!(orphan_resolution, payload)
      SplitWorkflowBroadcaster.call(project: orphan_resolution.project)
    end

    private

    def persist_draft_proposal!(orphan_resolution, payload)
      children = Array(payload["children"])
      orphan_resolution.split_proposals.draft.delete_all
      orphan_resolution.split_proposals.create!(
        status: :draft,
        version: next_version(orphan_resolution),
        feasible: payload.fetch("feasible", true),
        plan_reason: payload["reason"],
        child_piece_geometries: children,
        cut_segments: Array(payload["cut_segments"]),
        labels: children.map { |child| child["label"] }.compact
      )
    end

    def next_version(orphan_resolution)
      (orphan_resolution.split_proposals.maximum(:version) || 0) + 1
    end
  end
end
