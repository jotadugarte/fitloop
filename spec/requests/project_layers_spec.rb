# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project layers", type: :request do
  let(:project) { create_project_for_spec!(title: "DXF upload bench", pin: "445566") }
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

  describe "PATCH /projects/:project_id/layers [REQ-FIT-DXF-001]" do
    it "saves layer selection, starts nesting, and redirects to the project progress page" do
      unlock_project_for_spec!(project, pin: "445566")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSync.call(project)
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      layer.update!(included: false)

      expect do
        patch project_layers_path(project), params: {
          project_layers: { layer.id.to_s => { included: "1" } }
        }
      end.to have_enqueued_job(NestingJob)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to be_nil
      expect(layer.reload).to be_included
      expect(project.reload.status).to eq("processing")
    end
  end

  describe "POST /projects/:project_id/input_dxf_files [REQ-FIT-DXF-001]" do
    # Saved project: avoids ephemeral workspace session coupling (resolve! requires bound session).
    let(:project) do
      create_project_for_spec!(
        title: "DXF multi-upload bench",
        pin: "445566",
        ephemeral: false,
        bind_workspace: false
      )
    end

    it "accepts multiple DXF uploads in one request" do
      unlock_project_for_spec!(project, pin: "445566")

      post project_input_dxf_files_path(project), params: {
        files: [
          fixture_file_upload(sample_dxf, "first.dxf", "application/dxf"),
          fixture_file_upload(sample_dxf, "second.dxf", "application/dxf")
        ]
      }

      expect(response).to redirect_to(project_path(project))
      expect(project.reload.input_dxf.count).to eq(2)
    end
  end
end
