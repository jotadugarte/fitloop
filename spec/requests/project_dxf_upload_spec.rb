# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project DXF upload", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def start_setup_session!
    get start_project_path
    follow_redirect!
    Project.find(session[:workspace_project_id])
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
end
