# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::SplitPlanJob, type: :job do
  let(:project) { create_project_for_spec!(title: "Split plan bench", bind_workspace: false) }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }
  let(:orphan_resolution) do
    OrphanResolution.create!(
      project: project,
      piece_key: "0",
      reason: "oversized_for_sheet",
      resolution_state: :system_split
    )
  end
  let(:preview_payload) do
    {
      "piece_key" => "0",
      "feasible" => true,
      "reason" => nil,
      "children" => [
        {
          "label" => "a",
          "rings" => [ [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 100.0, 50.0 ], [ 0.0, 50.0 ] ] ]
        },
        {
          "label" => "b",
          "rings" => [ [ [ 100.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 50.0 ], [ 100.0, 50.0 ] ] ]
        }
      ],
      "cut_segments" => [
        [ [ 100.0, 0.0 ], [ 100.0, 50.0 ] ]
      ]
    }
  end

  before do
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)
    project.nesting_runs.create!(
      status: "partial",
      report_json: { "orphans" => [ { "piece_index" => 0, "reason" => "oversized_for_sheet" } ] },
      finished_at: Time.current
    )
    allow(Nesting::SplitPlannerRunner).to receive(:call).and_return(preview_payload)
  end

  describe "#perform [REQ-FIT-SPLIT-001] [REQ-FIT-JOB-001]" do
    it "[REQ-FIT-SPLIT-001] invokes SplitPlannerRunner and stores a draft SplitProposal" do
      allow(Nesting::SplitWorkflowBroadcaster).to receive(:call)

      described_class.perform_now(orphan_resolution.id)

      expect(Nesting::SplitPlannerRunner).to have_received(:call).with(
        orphan_resolution: orphan_resolution
      )
      expect(Nesting::SplitWorkflowBroadcaster).to have_received(:call).with(project: project)

      proposal = orphan_resolution.split_proposals.reload.sole
      expect(proposal.status).to eq("draft")
      expect(proposal.version).to eq(1)
      expect(proposal.child_piece_geometries).to eq(preview_payload.fetch("children"))
      expect(proposal.cut_segments).to eq(preview_payload.fetch("cut_segments"))
      expect(proposal.labels).to eq(%w[a b])
    end

    it "[REQ-FIT-JOB-001] can be enqueued for async execution" do
      expect {
        described_class.perform_later(orphan_resolution.id)
      }.to have_enqueued_job(described_class).with(orphan_resolution.id)
    end

    it "[REQ-FIT-SPLIT-001] stores split_not_feasible when planner cannot split" do
      allow(Nesting::SplitPlannerRunner).to receive(:call).and_return(
        preview_payload.merge(
          "feasible" => false,
          "reason" => "split_not_feasible",
          "children" => [],
          "cut_segments" => []
        )
      )

      described_class.perform_now(orphan_resolution.id)

      proposal = orphan_resolution.split_proposals.reload.sole
      expect(proposal.feasible).to be(false)
      expect(proposal.plan_reason).to eq("split_not_feasible")
      expect(proposal.child_piece_geometries).to eq([])
    end
  end
end
