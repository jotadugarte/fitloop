# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project source DXF preview", type: :request do
  let(:project) do
    create_project_for_spec!(
      title: "Source preview bench",
      pin: "556677",
      ephemeral: false,
      bind_workspace: false
    )
  end
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "GET /projects/:id" do
    it "renders the original DXF preview for included layers with layer colors" do
      unlock_project_for_spec!(project, pin: "556677")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-preview"')
      expect(response.body).to include('data-testid="source-dxf-preview-svg"')
      expect(response.body).to include('data-layer="PIECES"')
      expect(response.body).to include("<path")
      expect(response.body).to include(I18n.t("projects.show.source_dxf_detail_summary"))
    end

    it "renders clipped auxiliary geometry when primary and auxiliary layers are set [REQ-FIT-DXF-002]" do
      composite_fixture = Rails.root.join("nesting_engine/tests/fixtures/composite-piece-count.dxf")
      unlock_project_for_spec!(project, pin: "556677")

      project.input_dxf.attach(
        io: File.open(composite_fixture),
        filename: "composite-piece-count.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      attachment_id = project.input_dxf_attachments.first!.id
      cut = project.project_layers.find_by!(
        layer_name: "CORTE",
        active_storage_attachment_id: attachment_id
      )
      ProjectLayer::SetPrimary.call(cut)
      project.project_layers.find_by!(
        layer_name: "GRABADO",
        active_storage_attachment_id: attachment_id
      ).update!(included: true, layer_role: :auxiliary)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-layer="CORTE"')
      expect(response.body).to include('data-layer="GRABADO"')
      expect(response.body).not_to include('d="M 200')
    end

    it "shows empty state when no layers are selected for nesting" do
      unlock_project_for_spec!(project, pin: "556677")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-preview-empty"')
      expect(response.body).to include(I18n.t("projects.show.source_dxf_detail_summary"))
    end
  end
end
