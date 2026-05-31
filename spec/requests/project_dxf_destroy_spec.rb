# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project DXF destroy", "[REQ-FIT-UI-001]", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def start_setup_session!
    get start_project_path
    follow_redirect!
    Project.find(session[:workspace_project_id])
  end

  it "removes a DXF from Mi taller via turbo-stream" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    attachment = project.reload.input_dxf_attachments.first

    expect do
      delete project_input_dxf_file_path(project, attachment),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end.to change { project.reload.input_dxf_attachments.count }.from(1).to(0)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("source_dxf_detail_project_#{project.id}")
    expect(response.body).to include("dxf-files-layers__empty")
  end

  it "re-renders the layer list when delete is repeated (idempotent)" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    attachment = project.reload.input_dxf_attachments.first

    delete project_input_dxf_file_path(project, attachment),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)

    delete project_input_dxf_file_path(project, attachment),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("dxf-files-layers__empty")
  end
end
