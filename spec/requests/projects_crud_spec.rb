# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workshop configuration (ephemeral)", "[REQ-FIT-UI-001]", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "PATCH /taller workspace and nesting parameters" do
    it "persists nesting parameters and sheet inventory from Mi taller" do
      project = begin_workspace_session!

      post project_input_dxf_files_path(project),
           params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }
      project.reload
      pieces_layer = project.project_layers.find_by!(layer_name: "PIECES")

      patch nesting_parameters_project_path(project), params: {
        project: { kerf_mm: 2.5, margin_mm: 8 }
      }

      patch workspace_project_path(project), params: {
        section: "sheets",
        project: {
          sheet_stocks_attributes: {
            "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
          }
        }
      }

      patch workspace_project_path(project), params: {
        section: "layers",
        project_layers: {
          pieces_layer.active_storage_attachment_id.to_s => {
            pieces_layer.id.to_s => { included: "1" }
          }
        }
      }

      project.reload
      expect(project.kerf_mm).to eq(2.5)
      expect(project.margin_mm).to eq(8)
      expect(project.sheet_stocks.count).to eq(1)
    end
  end
end
