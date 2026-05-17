# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project layers", type: :request do
  let(:project) { Project.create!(title: "DXF upload bench", pin: "445566") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "GET /projects/:project_id/layers [REQ-FIT-DXF-001]" do
    it "shows a layer checklist built from union of uploaded DXF layer names" do
      unlock_project_for_spec!(project, pin: "445566")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece_a.dxf",
        content_type: "application/dxf"
      )

      get project_layers_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="layer-checklist"')
      expect(response.body).to include("PIECES")
    end
  end

  describe "POST /projects/:project_id/input_dxf_files [REQ-FIT-DXF-001]" do
    it "accepts multiple DXF uploads in one request" do
      unlock_project_for_spec!(project, pin: "445566")

      post project_input_dxf_files_path(project), params: {
        files: [
          fixture_file_upload(sample_dxf, "first.dxf", "application/dxf"),
          fixture_file_upload(sample_dxf, "second.dxf", "application/dxf")
        ]
      }

      expect(response).to redirect_to(project_layers_path(project))
      expect(project.reload.input_dxf.count).to eq(2)
    end
  end
end
