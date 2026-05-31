# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Re-nesting after sheet inventory edit", "[REQ-FIT-UI-001]", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  it "POST /projects/:id/nesting_runs succeeds after a workspace sheet save [REQ-FIT-UI-001]" do
    project = begin_workspace_session!

    post project_input_dxf_files_path(project),
         params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }
    project.reload
    cut = project.project_layers.find_by!(layer_name: "PIECES")
    ProjectLayer::SetPrimary.call(cut)

    patch workspace_project_path(project), params: {
      section: "sheets",
      project: {
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      }
    }

    post project_nesting_runs_path(project)
    expect(response).to redirect_to(workshop_path)

    project.reload
    project.nesting_runs.last.update!(status: "completed")
    project.update!(status: :completed)
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

    expect(response).to redirect_to(workshop_path)
  end
end
