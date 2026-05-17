# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project source DXF preview", type: :request do
  let(:project) { create_project_for_spec!(title: "Source preview bench", pin: "556677") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "GET /projects/:id" do
    it "renders the original DXF preview for included layers with layer colors" do
      unlock_project_for_spec!(project, pin: "556677")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSync.call(project)
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-preview"')
      expect(response.body).to include('data-testid="source-dxf-preview-svg"')
      expect(response.body).to include('data-layer="PIECES"')
      expect(response.body).to include("<path")
      expect(response.body).to include(I18n.t("projects.source_preview.title"))
    end

    it "shows empty state when no layers are selected for nesting" do
      unlock_project_for_spec!(project, pin: "556677")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSync.call(project)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-preview-empty"')
    end
  end
end
