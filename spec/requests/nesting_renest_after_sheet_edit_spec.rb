# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Re-nesting after sheet inventory edit", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  it "POST /projects/:id/nesting_runs succeeds after a workspace sheet save [REQ-FIT-UI-001]" do
    get start_project_path
    follow_redirect!
    project = Project.find(session[:workspace_project_id])

    post project_input_dxf_files_path(project),
         params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }
    project.reload
    pieces_layer = project.project_layers.find_by!(layer_name: "PIECES")

    patch project_path(project), params: {
      project: {
        kerf_mm: 0,
        margin_mm: 5,
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
    follow_redirect!

    post project_nesting_runs_path(project)
    expect(response).to redirect_to(project_path(project))

    project.reload
    first_stock = project.sheet_stocks.first

    patch workspace_project_path(project),
          params: {
            section: "sheets",
            project: {
              sheet_stocks_attributes: {
                "0" => {
                  id: first_stock.id,
                  width_mm: first_stock.width_mm,
                  height_mm: first_stock.height_mm,
                  quantity: first_stock.quantity,
                  sort_order: 0
                },
                "1" => { width_mm: 800, height_mm: 1600, quantity: 2, sort_order: 1 }
              }
            }
          },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)

    expect do
      post project_nesting_runs_path(project)
    end.to change { project.nesting_runs.count }.by(1)

    expect(response).to redirect_to(project_path(project))
  end
end
