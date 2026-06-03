# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project source DXF detail", type: :request do
  let(:project) { create_project_for_spec!(title: "Source DXF detail bench") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "GET /projects/:id" do
    it "renders Detalle DXF without per-file SVG preview (same as setup)" do
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("projects.show.source_dxf_detail_summary"))
      expect(response.body).to include('data-testid="dxf-file-entry"')
      expect(response.body).not_to include('data-testid="source-dxf-preview"')
      expect(response.body).not_to include('data-testid="source-dxf-preview-empty"')
      expect(response.body).not_to include('data-testid="source-dxf-layer-count"')
    end
  end
end
