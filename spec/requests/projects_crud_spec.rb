# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project setup (ephemeral)", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "PATCH /projects/:id (continue)" do
    it "persists nesting parameters and sheet inventory" do
      get start_project_path
      follow_redirect!
      project = Project.find(session[:workspace_project_id])

      post project_input_dxf_files_path(project),
           params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }
      project.reload
      pieces_layer = project.project_layers.find_by!(layer_name: "PIECES")

      patch project_path(project), params: {
        project: {
          kerf_mm: 2.5,
          margin_mm: 8,
          sheet_stocks_attributes: {
            "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
          }
        },
        project_layers: {
          pieces_layer.active_storage_attachment_id.to_s => {
            pieces_layer.id.to_s => { included: "1" }
          }
        }
      }

      project.reload
      expect(project.kerf_mm).to eq(2.5)
      expect(project.margin_mm).to eq(8)
      expect(project.curve_tolerance_mm).to eq(0.1)
      expect(project.sheet_gap_mm).to eq(15)
      expect(project.sheet_stocks.count).to eq(1)
    end

    it "re-renders setup when sheet inventory validation fails" do
      get start_project_path
      follow_redirect!
      project = Project.find(session[:workspace_project_id])

      patch project_path(project), params: {
        project: { kerf_mm: 0, margin_mm: 5 }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include(I18n.t("projects.new.setup_title"))
    end
  end
end
