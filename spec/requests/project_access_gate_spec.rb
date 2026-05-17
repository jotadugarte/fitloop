# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project PIN access", type: :request do
  let(:project) do
    Project.create!(
      title: "PIN gate bench",
      pin: "556688",
      status: :completed,
      sheet_stocks_attributes: {
        "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 }
      }
    )
  end

  describe "GET /projects [REQ-FIT-UI-003]" do
    it "lists projects without login" do
      project

      get projects_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="projects-index"')
      expect(response.body).to include("PIN gate bench")
    end
  end

  describe "GET /projects/:id [REQ-FIT-UI-003]" do
    it "shows the PIN gate before access is granted" do
      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="pin-gate"')
      expect(response.body).not_to include('data-testid="download-nested-dxf"')
    end

    it "unlocks the project with the user PIN" do
      post verify_pin_project_path(project), params: { pin: "556688" }

      expect(response).to redirect_to(project_path(project))
      follow_redirect!
      expect(response.body).not_to include('data-testid="pin-gate"')
      expect(response.body).to include("PIN gate bench")
    end

    it "offers nested DXF download after access is granted" do
      project.nested_dxf.attach(
        io: StringIO.new("NESTED"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      unlock_project_for_spec!(project, pin: "556688")

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="download-nested-dxf"')
      expect(response.body).to include('data-turbo="false"')
    end

    it "serves the nested DXF as a file download" do
      project.nested_dxf.attach(
        io: StringIO.new("NESTED DXF CONTENT"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      unlock_project_for_spec!(project, pin: "556688")

      get rails_blob_path(project.nested_dxf, disposition: "attachment", only_path: true)

      expect(response).to have_http_status(:redirect)
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("NESTED DXF CONTENT")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("nested.dxf")
    end
  end
end
