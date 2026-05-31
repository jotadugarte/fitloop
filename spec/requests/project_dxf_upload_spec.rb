# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project DXF upload", "[REQ-FIT-UI-001]", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def start_setup_session!
    get start_project_path
    follow_redirect!
    Project.find(session[:workspace_project_id])
  end

  it "[REQ-FIT-AUTH-001] requires workspace tab header when project is bound per tab (D21)" do
    tab_id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
    tab_headers = { "X-Workspace-Tab-Id" => tab_id }
    get start_project_path, headers: tab_headers
    follow_redirect!(headers: tab_headers)
    project = Workspace.find(session, tab_id: tab_id)
    expect(session[Workspace::WORKSPACES_KEY].keys).to eq([tab_id])

    post project_input_dxf_files_path(project, context: "setup"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to redirect_to(start_project_path)

    post project_input_dxf_files_path(project, context: "setup"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: {
           "Accept" => "text/vnd.turbo-stream.html",
           "X-Workspace-Tab-Id" => tab_id
         }

    expect(response).to have_http_status(:ok)
    expect(project.reload.input_dxf).to be_attached
  end

  it "accepts turbo-stream upload with files[] param from setup" do
    project = start_setup_session!

    post project_input_dxf_files_path(project, context: "setup"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(project.reload.input_dxf).to be_attached
    expect(response.body).to include("dxf_files_layers_project_#{project.id}")
    expect(response.body).not_to include("show_dxf_upload")
  end

  it "accepts turbo-stream upload with files param" do
    project = start_setup_session!

    post project_input_dxf_files_path(project, context: "setup"),
         params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(project.reload.input_dxf).to be_attached
  end

  it "expands layer checklists for newly uploaded files on Mi taller" do
    project = start_setup_session!

    post project_input_dxf_files_path(project, context: "show"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "first.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="dxf-file-entry"')
    expect(response.body).to match(/data-testid="dxf-file-entry"[^>]*open/m)
  end

  it "keeps existing file entries collapsed when uploading another DXF" do
    project = start_setup_session!

    post project_input_dxf_files_path(project, context: "show"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "first.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    post project_input_dxf_files_path(project, context: "show"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "second.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    body = response.body
    expect(body.scan(/data-testid="dxf-file-entry"/).size).to eq(2)
    expect(body.scan(/data-testid="dxf-file-entry"[^>]*open/m).size).to eq(1)
  end

  it "opens source DXF detail and expands new file layers after nesting on Mi taller" do
    project = start_setup_session!

    post project_input_dxf_files_path(project, context: "show"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "first.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)

    post project_input_dxf_files_path(project, context: "show"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "second.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    body = response.body
    expect(response).to have_http_status(:ok)
    expect(body).to include("data-collapsible-preserve-open")

    dxf_start = body.index('data-testid="source-dxf-detail"')
    dxf_tag = body.slice(dxf_start - 120, 280)
    expect(dxf_tag).to include(" open")
    expect(body.scan(/data-testid="dxf-file-entry"/).size).to eq(2)
    expect(body.scan(/data-testid="dxf-file-entry"[^>]*open/m).size).to eq(1)
  end

  it "updates source DXF detail on show via turbo-stream" do
    project = start_setup_session!

    post project_input_dxf_files_path(project, context: "setup"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }

    project.project_layers.find_by!(layer_name: "PIECES").update!(included: true)
    project.update!(status: :ready)
    Workspace.bind!(session, project)

    post project_input_dxf_files_path(project, context: "show"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "second.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("source_dxf_detail_project_#{project.id}")
    expect(response.body).to include('data-testid="dxf-upload-show-hint"')
    expect(response.body).not_to include("dxf_files_layers_project_#{project.id}")
    expect(project.reload.input_dxf_attachments.count).to eq(2)
  end
end
