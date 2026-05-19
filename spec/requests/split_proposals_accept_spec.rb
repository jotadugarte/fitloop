# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Split proposal accept", type: :request do
  def start_ephemeral_workspace!
    get start_project_path
    follow_redirect!
    Project.find(session[:workspace_project_id])
  end

  describe "POST accept [REQ-FIT-SPLIT-001]" do
    let(:project) { start_ephemeral_workspace! }
    let(:orphan_resolution) do
      OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :system_split
      )
    end
    let!(:proposal) do
      SplitProposal.create!(
        orphan_resolution: orphan_resolution,
        status: :draft,
        version: 1,
        labels: %w[a b],
        cut_segments: [ [ [ 100.0, 0.0 ], [ 100.0, 50.0 ] ] ],
        child_piece_geometries: [
          {
            "label" => "a",
            "rings" => [ [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 100.0, 50.0 ], [ 0.0, 50.0 ] ] ]
          },
          {
            "label" => "b",
            "rings" => [ [ [ 100.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 50.0 ], [ 100.0, 50.0 ] ] ]
          }
        ]
      )
    end

    it "[REQ-FIT-SPLIT-001] materializes DerivedPiece rows and resolves the mother orphan" do
      post project_accept_project_orphan_split_proposal_path(project, orphan_resolution.piece_key)

      expect(response).to redirect_to(project_path(project))
      expect(proposal.reload.status).to eq("accepted")

      derived = project.derived_pieces.order(:sort_order)
      expect(derived.size).to eq(2)
      expect(derived.map(&:parent_piece_key)).to all(eq("0"))
      expect(derived.map(&:label)).to eq(%w[Pieza-1a Pieza-1b])
      expect(derived.first.geometry_json.fetch("rings")).to be_present

      expect(orphan_resolution.reload.resolution_state).to eq("resolved")
    end

    it "[REQ-FIT-SPLIT-001] appends split_accepted to session_workflow_log" do
      post project_accept_project_orphan_split_proposal_path(project, orphan_resolution.piece_key)

      project.reload
      expect(project.session_workflow_log.last).to include(
        "event" => "split_accepted",
        "piece_key" => "0",
        "split_proposal_id" => proposal.id
      )
    end
  end
end
