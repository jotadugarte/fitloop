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
    expect(session[Workspace::WORKSPACES_KEY].keys).to eq([ tab_id ])

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to redirect_to(start_project_path)

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: {
           "Accept" => "text/vnd.turbo-stream.html",
           "X-Workspace-Tab-Id" => tab_id
         }

    expect(response).to have_http_status(:ok)
    expect(project.reload.input_dxf).to be_attached
  end

  it "accepts turbo-stream upload with files[] param on Mi taller" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(project.reload.input_dxf).to be_attached
    expect(response.body).to include("source_dxf_detail_project_#{project.id}")
    expect(response.body).to include('data-testid="source-dxf-detail"')
  end

  it "returns unprocessable content when no files are posted" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: {},
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "redirects HTML uploads without files back to the workshop with an alert" do
    project = start_setup_session!

    post project_input_dxf_files_path(project), params: {}

    expect(response).to redirect_to(workshop_path)
    expect(flash[:alert]).to eq(I18n.t("project_layers.upload.missing"))
  end

  it "accepts turbo-stream upload with files param" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(project.reload.input_dxf).to be_attached
  end

  it "expands layer checklists for newly uploaded files on Mi taller" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "first.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML.fragment(response.body)
    expect(doc.css('details[data-testid="dxf-file-entry"]')).not_to be_empty
    expect(doc.css('details[data-testid="dxf-file-entry"][open]')).not_to be_empty
  end

  it "keeps existing file entries collapsed when uploading another DXF" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "first.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "second.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    doc = Nokogiri::HTML.fragment(response.body)
    expect(doc.css('details[data-testid="dxf-file-entry"]').size).to eq(2)
    expect(doc.css('details[data-testid="dxf-file-entry"][open]').size).to eq(1)
  end

  it "opens source DXF detail and expands new file layers after nesting on Mi taller" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "first.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "second.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    doc = Nokogiri::HTML.fragment(response.body)
    expect(doc.css('[data-collapsible-preserve-open]')).not_to be_empty
    expect(doc.css('details[data-testid="source-dxf-detail"][open]')).not_to be_empty
    expect(doc.css('details[data-testid="dxf-file-entry"]').size).to eq(2)
    expect(doc.css('details[data-testid="dxf-file-entry"][open]').size).to eq(1)
  end

  it "updates source DXF detail via turbo-stream on subsequent uploads" do
    project = start_setup_session!

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    post project_input_dxf_files_path(project),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "second.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("source_dxf_detail_project_#{project.id}")
    expect(response.body).to include('data-testid="dxf-upload-show-hint"')
    expect(project.reload.input_dxf_attachments.count).to eq(2)
  end

  describe "invalid file uploads" do
    let(:project) { start_setup_session! }

    it "rejects file larger than 10MB via HTML upload" do
      large_file = Tempfile.new([ "large", ".dxf" ])
      File.binwrite(large_file.path, "SECTION\n" + ("X" * (10.megabytes + 1)))

      post project_input_dxf_files_path(project),
           params: { files: [ fixture_file_upload(large_file.path, "large.dxf", "application/dxf") ] }

      expect(response).to redirect_to(workshop_path)
      expect(flash[:alert]).to include("too large")
      expect(project.reload.input_dxf).not_to be_attached
    ensure
      large_file.close
      large_file.unlink
    end

    it "rejects file without .dxf extension via HTML upload" do
      txt_file = Tempfile.new([ "valid", ".txt" ])
      File.binwrite(txt_file.path, "  0\nSECTION\n  2\nHEADER\n  0\nENDSEC")

      post project_input_dxf_files_path(project),
           params: { files: [ fixture_file_upload(txt_file.path, "valid.txt", "text/plain") ] }

      expect(response).to redirect_to(workshop_path)
      expect(flash[:alert]).to include("extension")
      expect(project.reload.input_dxf).not_to be_attached
    ensure
      txt_file.close
      txt_file.unlink
    end

    it "rejects file without SECTION marker via HTML upload" do
      corrupt_file = Tempfile.new([ "corrupt", ".dxf" ])
      File.binwrite(corrupt_file.path, "  0\nINVALID\n  0\nENDSEC")

      post project_input_dxf_files_path(project),
           params: { files: [ fixture_file_upload(corrupt_file.path, "corrupt.dxf", "application/dxf") ] }

      expect(response).to redirect_to(workshop_path)
      expect(flash[:alert]).to include("corrupt")
      expect(project.reload.input_dxf).not_to be_attached
    ensure
      corrupt_file.close
      corrupt_file.unlink
    end

    it "rejects file without SECTION marker via Turbo Stream upload" do
      corrupt_file = Tempfile.new([ "corrupt", ".dxf" ])
      File.binwrite(corrupt_file.path, "  0\nINVALID\n  0\nENDSEC")

      post project_input_dxf_files_path(project),
           params: { files: [ fixture_file_upload(corrupt_file.path, "corrupt.dxf", "application/dxf") ] },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to redirect_to(workshop_path)
      expect(response).to have_http_status(:see_other)
      expect(flash[:alert]).to include("corrupt")
      expect(project.reload.input_dxf).not_to be_attached
    ensure
      corrupt_file.close
      corrupt_file.unlink
    end
  end
end
