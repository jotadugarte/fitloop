# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workspace project access", "[REQ-FIT-AUTH-001] [REQ-FIT-UI-003] [REQ-FIT-BILL-001]", type: :request do
  describe "GET /projects [REQ-FIT-UI-003]" do
    it "redirects to empezar (ephemeral-only; no saved project list)" do
      get projects_path

      expect(response).to redirect_to(start_project_path)
    end
  end

  describe "GET /taller without session bind [REQ-FIT-AUTH-001]" do
    it "redirects to empezar when no workshop is bound to the session" do
      get start_project_path
      follow_redirect!
      Workspace.discard!(session, tab_id: Workspace::DEFAULT_TAB_ID)

      get workshop_path

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

    it "redirects nested DXF download to paywall without entitlement [REQ-FIT-BILL-001]" do
      project.nesting_runs.create!(status: "completed")
      project.nested_dxf.attach(
        io: StringIO.new("NESTED DXF CONTENT"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      get nested_dxf_project_path(project)

      expect(response).to redirect_to(download_paywall_project_path(project))
    end
  end

  describe "SetsWorkspaceProject concern edge cases" do
    let(:tab_a) { "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }

    it "creates a workspace project when session is completely empty" do
      get workshop_path
      expect(response).to have_http_status(:ok)
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      expect(project).to be_present
      expect(project.ephemeral?).to be(true)
    end

    it "uses params[:project_id] if present" do
      project = start_workspace_for_tab!(tab_a)
      post cart_path, params: { project_id: project.id, kind: "plan", tier_months: "4" }, headers: tab_headers(tab_a)
      expect(response).to redirect_to(checkout_path)
    end

    it "recovers workspace project when project does not exist" do
      post cart_path, params: { project_id: 999999, kind: "plan", tier_months: "4" }
      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
    end

    it "clears stale workspace binds for non-existent project" do
      allow(Workspace).to receive(:resolve!).and_raise(ActiveRecord::RecordNotFound)
      fake_session = { Workspace::WORKSPACES_KEY => { "tab-1" => 999999 }, Workspace::SESSION_KEY => 999999 }
      allow_any_instance_of(ApplicationController).to receive(:session).and_return(fake_session)

      post cart_path, params: { project_id: 999999, kind: "plan", tier_months: "4" }
      expect(fake_session[Workspace::WORKSPACES_KEY]).to eq({})
      expect(fake_session[Workspace::SESSION_KEY]).to be_nil
    end

    it "returns false when project is not bound to the session" do
      project = Project.create!(ephemeral: true, title: "Unbound Project")
      allow(Workspace).to receive(:resolve!).and_raise(ActiveRecord::RecordNotFound)
      fake_session = { Workspace::WORKSPACES_KEY => { "tab-1" => 111111 } }
      allow_any_instance_of(ApplicationController).to receive(:session).and_return(fake_session)

      post cart_path, params: { project_id: project.id, kind: "plan", tier_months: "4" }
      expect(response).to redirect_to(start_project_path)
    end

    it "returns false if the project is already the active project for the current tab" do
      project = Project.create!(ephemeral: true, title: "Active Project")
      allow(Workspace).to receive(:resolve!).and_raise(ActiveRecord::RecordNotFound)
      allow(Workspace).to receive(:bound_to_project?).and_return(true)
      allow(Workspace).to receive(:find).with(anything, tab_id: "tab-1").and_return(project)
      allow_any_instance_of(ApplicationController).to receive(:workspace_tab_id).and_return("tab-1")

      post cart_path, params: { project_id: project.id, kind: "plan", tier_months: "4" }
      expect(response).to redirect_to(start_project_path)
    end

    it "returns false when project is owned by another tab and the current tab already has an active project" do
      project1 = Project.create!(ephemeral: true, title: "P1")
      project2 = Project.create!(ephemeral: true, title: "P2")
      allow(Workspace).to receive(:resolve!).and_raise(ActiveRecord::RecordNotFound)
      allow(Workspace).to receive(:bound_to_project?).and_return(true)
      allow(Workspace).to receive(:tab_id_for_project).and_return("tab-1")
      allow(Workspace).to receive(:find).with(anything, tab_id: "tab-2").and_return(project2)
      allow_any_instance_of(ApplicationController).to receive(:workspace_tab_id).and_return("tab-2")

      post cart_path, params: { project_id: project1.id, kind: "plan", tier_months: "4" }
      expect(response).to redirect_to(start_project_path)
    end

    it "binds the project to the current tab and returns true" do
      project = Project.create!(ephemeral: true, title: "P3")
      allow(Workspace).to receive(:resolve!).and_raise(ActiveRecord::RecordNotFound)
      allow(Workspace).to receive(:bound_to_project?).and_return(true)
      allow(Workspace).to receive(:tab_id_for_project).and_return(nil)
      allow(Workspace).to receive(:find).with(anything, tab_id: "tab-1").and_return(nil)
      allow_any_instance_of(ApplicationController).to receive(:workspace_tab_id).and_return("tab-1")

      expect(Workspace).to receive(:bind!).with(anything, project, tab_id: "tab-1")

      post cart_path, params: { project_id: project.id, kind: "plan", tier_months: "4" }
      expect(response).to redirect_to(checkout_path)
    end

    it "expires project everywhere when param_id is present and tab is expired" do
      project = Project.create!(ephemeral: true, title: "P4")
      allow_any_instance_of(CartController).to receive(:tab_return_expired?).and_return(true)
      allow(Workspace).to receive(:bound_to_project?).and_return(true)

      expect(Workspace).to receive(:expire_project_everywhere!).with(anything, project, anything)

      post cart_path, params: { project_id: project.id, kind: "plan", tier_months: "4" }
      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.tab_closed_expired"))
    end

    it "expires tab after closure when project is nil and tab is expired" do
      allow_any_instance_of(ProjectsController).to receive(:tab_return_expired?).and_return(true)
      allow(Workspace).to receive(:find).and_return(nil)
      allow(Workspace).to receive(:any_bound_project).and_return(nil)

      expect(Workspace).to receive(:expire_tab_after_closure!).with(anything, tab_id: anything, request: anything)

      get workshop_path
      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.tab_closed_expired"))
    end
  end
end


