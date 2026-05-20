# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nesting start with ephemeral workspace", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  it "redirects to empezar when the workspace project was discarded" do
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
        pieces_layer.id.to_s => { included: "1" }
      }
    }
    follow_redirect!

    project_id = project.id
    get root_path
    expect(Project.exists?(project_id)).to be(false)

    post project_nesting_runs_path(project_id), params: {}
    expect(response).to redirect_to(start_project_path)
    expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
  end
end
