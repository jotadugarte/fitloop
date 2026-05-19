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
      accepted_event = project.session_workflow_log.find { |entry| entry["event"] == "split_accepted" }
      expect(accepted_event).to include(
        "piece_key" => "0",
        "split_proposal_id" => proposal.id
      )
    end

    it "[REQ-FIT-SPLIT-001] logs splits_ready_for_nest and exposes nest CTA after accept" do
      project.update!(status: :partial)
      project.nested_dxf.attach(
        io: StringIO.new("NESTED"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      post project_accept_project_orphan_split_proposal_path(project, orphan_resolution.piece_key)

      project.reload
      expect(project.session_workflow_log.last).to include(
        "event" => "splits_ready_for_nest",
        "derived_piece_count" => 2
      )

      get project_path(project)
      expect(response.body).to include(I18n.t("nesting.nest_updated_pieces"))
      expect(response.body).to include('data-testid="nest-updated-pieces"')
    end

    it "[REQ-FIT-SPLIT-001] shows derived piece titles and bounding dimensions after accept" do
      project.update!(status: :partial)
      project.placements_json.attach(
        io: StringIO.new(
          {
            sheets: [],
            orphans: [
              {
                piece_index: 0,
                piece_key: "0",
                reason: "oversized_for_sheet",
                width_mm: 200.0,
                height_mm: 50.0,
                offset_x_mm: 0.0,
                offset_y_mm: 0.0,
                rings: [ [ [ 0.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 50.0 ], [ 0.0, 50.0 ] ] ]
              }
            ]
          }.to_json
        ),
        filename: "placements.json",
        content_type: "application/json"
      )

      post project_accept_project_orphan_split_proposal_path(project, orphan_resolution.piece_key)

      get project_path(project)

      expect(response.body).to include(
        I18n.t("nesting.derived_piece.title", piece_number: 1, suffix: "A")
      )
      expect(response.body).to include(
        I18n.t("nesting.derived_piece.title", piece_number: 1, suffix: "B")
      )
      expect(response.body).to include(
        I18n.t(
          "nesting.orphan_preview.dimensions",
          width: "100",
          height: "50"
        )
      )
      expect(response.body).to include('data-testid="orphan-derived-dimensions"')
    end
  end
end
