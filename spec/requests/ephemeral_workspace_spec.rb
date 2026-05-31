# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Ephemeral workspace", "[REQ-FIT-AUTH-001] [REQ-FIT-UI-001]", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  it "starts from empezar and lands on Mi taller in setup mode" do
    get start_project_path
    follow_redirect!

    expect(response).to have_http_status(:ok)
    expect(request.path).to eq(workshop_path)
    expect(response.body).to include('data-workshop-setup-mode="true"')
    expect(response.body).to include(I18n.t("projects.setup.welcome.intro"))
    expect(response.body).to include('data-testid="setup-welcome"')
    expect(response.body).to include('data-testid="setup-nesting-settings"')
    expect(response.body).not_to include('data-testid="show-preview-zone"')
    expect(response.body).not_to include(I18n.t("projects.form.continue"))
    expect(response.body).not_to include('name="project[pin]"')
  end

  it "switches to taller mode after the first nesting run" do
    project = begin_workspace_session!

    post project_input_dxf_files_path(project),
         params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }
    project.reload
    pieces_layer = project.project_layers.find_by!(layer_name: "PIECES")
    project.project_layers.find_by!(layer_name: "PIECES").update!(included: true)

    patch workspace_project_path(project), params: {
      section: "sheets",
      project: {
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      }
    }

    project.nesting_runs.create!(status: "failed", params_snapshot: {})

    get workshop_path

    expect(response.body).to include('data-workshop-setup-mode="false"')
    expect(response.body).to include('data-testid="show-welcome"')
    expect(response.body).to include(I18n.t("projects.show.nesting_parameters_title"))
  end

  it "switches to taller mode after POST nesting_runs creates a run" do
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

    get workshop_path

    expect(response.body).to include('data-workshop-setup-mode="false"')
    expect(response.body).to include('data-testid="show-welcome"')
    expect(project.reload.nesting_runs.count).to eq(1)
  end

  it "[REQ-FIT-AUTH-001] serves only the session-bound workshop at /taller" do
    get start_project_path
    follow_redirect!
    bound = Project.find(session[:workspace_project_id])

    other = Project.create!(
      ephemeral: true,
      title: "Other session project",
      status: :draft,
      sheet_stocks_attributes: {
        "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 }
      }
    )

    get workshop_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("sheet_inventory_project_#{bound.id}")
    expect(response.body).not_to include("sheet_inventory_project_#{other.id}")
    expect(bound).to be_persisted
    expect(other).to be_persisted
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
