# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workshop telemetry instrumentation", "[REQ-FIT-ANALYTICS-001]", type: :request do
  include ActiveJob::TestHelper

  let(:user) { create_billing_user!(email: "workshop-telemetry@example.com") }

  before do
    allow_any_instance_of(User).to receive(:send_on_create_confirmation_instructions)
  end

  describe "workspace_started event" do
    it "tracks workspace_started when a new workspace is created" do
      # Starting a project (GET /empezar or similar start action) should trigger Workspace.create!
      expect {
        get start_project_path
      }.to have_enqueued_job(TrackEventJob).with("workspace_started", anything)
    end
  end

  describe "first_dxf_uploaded event" do
    it "tracks first_dxf_uploaded with properties when the first DXF is attached" do
      # Initialize workspace first
      get start_project_path
      project_id = session[:workspaces]["__default__"]
      project = Project.find(project_id)

      expect(project.input_dxf_attachments).to be_empty

      # Upload the first DXF
      fixture_file = fixture_file_upload(
        Rails.root.join("spec/fixtures/golden/sample_piece.dxf"),
        "application/dxf"
      )

      expect {
        post project_input_dxf_files_path(project_id),
             params: { files: [ fixture_file ] }
      }.to have_enqueued_job(TrackEventJob).with("first_dxf_uploaded", hash_including(
        "properties" => hash_including(
          "filename" => "sample_piece.dxf",
          "byte_size" => anything,
          "layers" => anything
        )
      ))
    end
  end

  describe "project_discarded event" do
    it "tracks project_discarded synchronously with metadata snapshot when workspace is discarded" do
      # Initialize workspace first
      get start_project_path
      project_id = session[:workspaces]["__default__"]
      project = Project.find(project_id)
      project.update!(kerf_mm: 2.0, margin_mm: 10.0)

      # Visit start project path again, which discards the prior project
      expect {
        get start_project_path
      }.to change(UserEvent, :count).by(1)

      event = UserEvent.last
      expect(event.event_type).to eq("project_discarded")
      expect(event.priority).to eq("critical")
      expect(event.properties["kerf_mm"]).to eq(2.0)
      expect(event.properties["margin_mm"]).to eq(10.0)
    end
  end
end
