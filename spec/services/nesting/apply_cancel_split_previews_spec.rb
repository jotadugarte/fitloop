# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ApplyCancel do
  describe ".call [REQ-FIT-JOB-001] [REQ-FIT-SPLIT-001]" do
    let(:project) do
      Project.create!(
        title: "Cancel split previews",
        ephemeral: true,
        status: :processing,
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      )
    end
    let(:nesting_run) do
      project.nesting_runs.create!(
        status: "processing",
        params_snapshot: {},
        cancel_requested_at: Time.current
      )
    end

    it "[REQ-FIT-SPLIT-001] deletes draft SplitProposal rows for the project" do
      resolution = OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :system_split
      )
      draft = resolution.split_proposals.create!(
        status: :draft,
        version: 1,
        feasible: false,
        plan_reason: "split_not_feasible",
        child_piece_geometries: [],
        cut_segments: [],
        labels: []
      )
      accepted = resolution.split_proposals.create!(
        status: :accepted,
        version: 2,
        child_piece_geometries: [],
        cut_segments: [],
        labels: []
      )

      described_class.call(nesting_run: nesting_run)

      expect(SplitProposal.exists?(draft.id)).to be(false)
      expect(SplitProposal.exists?(accepted.id)).to be(true)
    end

    it "[REQ-FIT-JOB-001] is idempotent when the run is no longer processing" do
      nesting_run.update!(status: "failed", finished_at: Time.current)

      expect(described_class.call(nesting_run: nesting_run)).to be(false)
    end
  end
end
