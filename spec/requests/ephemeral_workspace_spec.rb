# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ephemeral workspace", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  it "starts from home and shows initial parameters" do
    get start_project_path
    follow_redirect!
    expect(response.body).to include(I18n.t("projects.new.setup_title"))
    expect(response.body).to include(I18n.t("projects.setup.welcome.intro"))
    expect(response.body).to include('data-testid="setup-welcome"')
    expect(response.body).to include(I18n.t("projects.form.continue"))
    expect(response.body).not_to include('name="project[pin]"')
    expect(response.body).not_to include('name="project[title]"')
  end

  it "continues to the project show page after setup" do
    get start_project_path
    follow_redirect!
    project = Project.find(session[:workspace_project_id])

    post project_input_dxf_files_path(project),
         params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }
    expect(response).to have_http_status(:ok).or have_http_status(:found)
    project.reload
    expect(project.input_dxf).to be_attached
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

    expect(response).to redirect_to(project_path(project))
    follow_redirect!
    expect(response.body).to include('data-testid="show-welcome"')
    expect(response.body).to include(I18n.t("projects.show.welcome.intro"))
    expect(response.body).to include(I18n.t("projects.show.nesting_parameters_title"))
    expect(response.body).to include(I18n.t("projects.show.session_title"))
  end

  it "discards the workspace when returning home" do
    get start_project_path
    follow_redirect!
    workspace_id = session[:workspace_project_id]
    expect(workspace_id).to be_present

    get root_path
    expect(Project.exists?(workspace_id)).to be(false)
    expect(session[:workspace_project_id]).to be_nil
  end
end
