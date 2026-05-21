# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workspace project access", type: :request do
  describe "GET /projects [REQ-FIT-UI-003]" do
    it "redirects to empezar (ephemeral-only; no saved project list)" do
      get projects_path

      expect(response).to redirect_to(start_project_path)
    end
  end

  describe "GET /projects/:id without session bind [REQ-FIT-AUTH-001]" do
    it "redirects to empezar when the project is not bound to the session" do
      get start_project_path
      follow_redirect!

      foreign = ProjectSpecFactory.create!(
        title: "Other workspace",
        status: :completed,
        sheet_stocks_attributes: {
          "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 }
        }
      )

      get project_path(foreign)

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
    end
  end

  describe "GET /projects/:id with session bind [REQ-FIT-AUTH-001] [REQ-FIT-UI-003]" do
    let(:project) do
      get start_project_path
      follow_redirect!

      record = Project.find(session[Workspace::SESSION_KEY])
      record.update!(
        title: "Workspace bench",
        status: :completed,
        sheet_stocks_attributes: {
          "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 }
        }
      )
      record
    end

    it "shows the project when the session is bound" do
      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-testid="pin-gate"')
      expect(response.body).to include('data-testid="project-show"')
      expect(response.body).to include(I18n.t("projects.show.session_title"))
    end

    it "offers nested DXF download when nested output exists" do
      project.nested_dxf.attach(
        io: StringIO.new("NESTED"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

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

      get nested_dxf_project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("NESTED DXF CONTENT")
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(response.headers["Content-Disposition"]).to include("nested.dxf")
    end
  end
end
