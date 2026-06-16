# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project source DXF detail", type: :request do
  let(:project) { create_project_for_spec!(title: "Source DXF detail bench") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "GET /projects/:id" do
    it "renders source DXF preview groups when layers are included and have polylines" do
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
      expect(response.body).to include('data-testid="source-dxf-valid-group"')
    end

    it "renders empty preview message when no layers are included" do
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.update_all(included: false)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-preview-empty"')
      expect(response.body).not_to include('data-testid="source-dxf-valid-group"')
    end

    it "renders proposed auto-close lines with zoomed viewBox when auto_close_gaps is enabled and gap <= 15.0 mm" do
      layer_data = {
        "width_mm" => 100.0,
        "height_mm" => 100.0,
        "offset_x_mm" => 0.0,
        "offset_y_mm" => 0.0,
        "layers" => [
          {
            "name" => "PIECES",
            "color" => "#ff0000",
            "polylines" => [[[5.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0], [0.0, 0.0]]],
            "polyline_open_flags" => [true],
            "gaps" => [
              {
                "distance_mm" => 5.0,
                "start" => [5.0, 0.0],
                "end" => [0.0, 0.0],
                "auto_closed" => true
              }
            ],
            "auto_close_lines" => [[[5.0, 0.0], [0.0, 0.0]]]
          }
        ]
      }
      allow(Dxf::SourcePreviewReader).to receive(:preview).and_return(layer_data)

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true, auto_close_gaps: true)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-open-group"')
      expect(response.body).to include('data-testid="proposed-auto-close-line"')
      expect(response.body).not_to include('data-testid="gap-error-circle"')
      expect(response.body).not_to include('viewBox="0 0 100.0 100.0"')
    end

    it "renders open preview from gaps_detected when Python preview omits warnable layer gaps" do
      layer_data = {
        "width_mm" => 100.0,
        "height_mm" => 100.0,
        "offset_x_mm" => 0.0,
        "offset_y_mm" => 0.0,
        "layers" => [
          {
            "name" => "PIECES",
            "color" => "#ff0000",
            "polylines" => [[[0.0, 0.0], [100.0, 0.0], [100.0, 50.0], [0.0, 50.0], [0.0, 0.0]]],
            "polyline_open_flags" => [false],
            "gaps" => [],
            "auto_close_lines" => []
          }
        ]
      }
      allow(Dxf::SourcePreviewReader).to receive(:preview).and_return(layer_data)

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.find_by!(layer_name: "PIECES").update!(
        included: true,
        gaps_detected: [
          {
            "distance_mm" => 14.8,
            "start" => [20.0, 0.0],
            "end" => [0.0, 0.0]
          }
        ]
      )

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-open-group"')
      expect(response.body).to include('data-testid="gap-error-circle"')
      expect(response.body).to include('data-testid="source-dxf-valid-group"')
    end

    it "does not render open preview from gaps_detected on unselected marking layers" do
      layer_data = {
        "width_mm" => 100.0,
        "height_mm" => 100.0,
        "offset_x_mm" => 0.0,
        "offset_y_mm" => 0.0,
        "layers" => [
          {
            "name" => "CORTE",
            "color" => "#ff0000",
            "polylines" => [[[0.0, 0.0], [100.0, 0.0], [100.0, 50.0], [0.0, 50.0], [0.0, 0.0]]],
            "polyline_open_flags" => [false],
            "gaps" => [],
            "auto_close_lines" => []
          }
        ]
      }
      allow(Dxf::SourcePreviewReader).to receive(:preview).and_return(layer_data)

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      attachment = project.input_dxf_attachments.first!
      corte = project.project_layers.find_by!(layer_name: "PIECES")
      marcado = project.project_layers.create!(
        layer_name: "MARCADO",
        active_storage_attachment_id: attachment.id,
        included: false,
        gaps_detected: [
          { "distance_mm" => 158.1, "start" => [20.0, 0.0], "end" => [0.0, 0.0] }
        ]
      )
      ProjectLayer::SetPrimary.call(corte)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-testid="source-dxf-open-group"')
      expect(response.body).not_to include('data-testid="gap-error-circle"')
    end

    it "omits ignored gaps from open preview and keeps full viewBox when gap > 15.0 mm" do
      layer_data = {
        "width_mm" => 100.0,
        "height_mm" => 100.0,
        "offset_x_mm" => 0.0,
        "offset_y_mm" => 0.0,
        "layers" => [
          {
            "name" => "PIECES",
            "color" => "#ff0000",
            "polylines" => [[[20.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0], [0.0, 0.0]]],
            "polyline_open_flags" => [true],
            "gaps" => [
              {
                "distance_mm" => 20.0,
                "start" => [20.0, 0.0],
                "end" => [0.0, 0.0],
                "auto_closed" => false
              }
            ],
            "auto_close_lines" => []
          }
        ]
      }
      allow(Dxf::SourcePreviewReader).to receive(:preview).and_return(layer_data)

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true, auto_close_gaps: false)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-open-group"')
      expect(response.body).not_to include('data-testid="proposed-auto-close-line"')
      expect(response.body).not_to include('data-testid="gap-error-circle"')
      expect(response.body).to include('viewBox="0 0 100.0 100.0"')
    end

    it "renders proposed auto-close line before authorization when gap is warnable" do
      layer_data = {
        "width_mm" => 100.0,
        "height_mm" => 100.0,
        "offset_x_mm" => 0.0,
        "offset_y_mm" => 0.0,
        "layers" => [
          {
            "name" => "PIECES",
            "color" => "#ff0000",
            "polylines" => [[[5.0, 0.0], [100.0, 0.0], [100.0, 100.0], [0.0, 100.0], [0.0, 0.0]]],
            "polyline_open_flags" => [true],
            "gaps" => [
              {
                "distance_mm" => 5.0,
                "start" => [5.0, 0.0],
                "end" => [0.0, 0.0],
                "auto_closed" => false
              }
            ],
            "auto_close_lines" => [[[5.0, 0.0], [0.0, 0.0]]]
          }
        ]
      }
      allow(Dxf::SourcePreviewReader).to receive(:preview).and_return(layer_data)

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true, auto_close_gaps: false)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="proposed-auto-close-line"')
      expect(response.body).to include('data-testid="gap-error-circle"')
    end

    it "renders 015 with open and valid preview panels when CORTE is primary and MARCADO is auxiliary", :slow do
      dxf_015 = Rails.root.join("nesting_engine/tests/fixtures/individuals/015.dxf")
      project.input_dxf.attach(
        io: File.open(dxf_015),
        filename: "015.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      attachment = project.input_dxf_attachments.first!
      corte = project.project_layers.find_by!(
        layer_name: "CORTE",
        active_storage_attachment_id: attachment.id
      )
      marcado = project.project_layers.find_by!(
        layer_name: "MARCADO",
        active_storage_attachment_id: attachment.id
      )

      ProjectLayer::SetPrimary.call(corte)
      marcado.update!(layer_role: :auxiliary, included: true)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="source-dxf-open-group"')
      expect(response.body).to include('data-testid="source-dxf-valid-group"')
      expect(response.body).to include('data-testid="proposed-auto-close-line"')
      expect(response.body).to include('data-testid="auto-close-gaps-checkbox"')
    end
  end
end
