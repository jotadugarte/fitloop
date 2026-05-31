# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Split proposal not feasible [REQ-FIT-SPLIT-001]", type: :request do
  let(:project) { start_ephemeral_workspace! }
  let(:orphan_resolution) do
    OrphanResolution.create!(
      project: project,
      piece_key: "0",
      reason: "no_sheet_capacity",
      resolution_state: :system_split
    )
  end
  let!(:proposal) do
    orphan_resolution.split_proposals.create!(
      status: :draft,
      version: 1,
      feasible: false,
      plan_reason: "split_not_feasible",
      child_piece_geometries: [],
      cut_segments: [],
      labels: []
    )
  end

  before do
    project.nesting_runs.create!(
      status: "partial",
      report_json: { "orphans" => [ { "piece_index" => 0, "reason" => "no_sheet_capacity" } ] },
      finished_at: Time.current
    )
    project.placements_json.attach(
      io: StringIO.new(
        {
          sheets: [],
          orphans: [
            {
              piece_index: 0,
              reason: "no_sheet_capacity",
              width_mm: 800.0,
              height_mm: 400.0,
              offset_x_mm: 0.0,
              offset_y_mm: 0.0,
              rings: [ [ [ 0.0, 0.0 ], [ 800.0, 0.0 ], [ 800.0, 400.0 ], [ 0.0, 400.0 ] ] ]
            }
          ]
        }.to_json
      ),
      filename: "placements.json",
      content_type: "application/json"
    )
    project.update!(status: :partial)
  end

  describe "GET project show [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] shows split_not_feasible error without accept button" do
      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="split-not-feasible"')
      expect(response.body).to include(I18n.t("nesting.split.not_feasible"))
      expect(response.body).not_to include(I18n.t("nesting.split.accept"))
    end
  end

  describe "POST accept [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] blocks accepting an infeasible split proposal" do
      post accept_project_orphan_split_proposal_path(project, orphan_resolution.piece_key)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq(I18n.t("nesting.split.not_feasible_accept"))
      expect(proposal.reload.status).to eq("draft")
      expect(project.derived_pieces.count).to eq(0)
    end
  end
end
