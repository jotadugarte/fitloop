# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workspace tab isolation", "[REQ-FIT-AUTH-001]", type: :request do
  def tab_headers(tab_id)
    { "X-Workspace-Tab-Id" => tab_id }
  end

  def start_workspace_for_tab!(tab_id)
    headers = tab_headers(tab_id)
    get start_project_path, headers: headers
    expect(response).to redirect_to(new_project_path)
    get new_project_path, headers: headers
    Workspace.find(session, tab_id: tab_id)
  end

  let(:tab_a) { "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }
  let(:tab_b) { "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" }

  describe "multi-tab bind [REQ-FIT-AUTH-001]" do
    it "[REQ-FIT-AUTH-001] keeps independent ephemeral projects per tab_id (D21)" do
      project_a = start_workspace_for_tab!(tab_a)
      project_b = start_workspace_for_tab!(tab_b)

      expect(project_a.id).not_to eq(project_b.id)
      expect(session[Workspace::WORKSPACES_KEY]).to include(
        tab_a => project_a.id,
        tab_b => project_b.id
      )
    end

    it "[REQ-FIT-AUTH-001] resolves nested DXF download with tab cookie when header is absent (D21)" do
      project = start_workspace_for_tab!(tab_a)
      run = project.nesting_runs.create!(status: "completed")
      project.nested_dxf.attach(
        io: StringIO.new("NESTED"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      cookies["fitloop_workspace_tab_id"] = tab_a
      get nested_dxf_project_path(project)

      expect(response).to redirect_to(%r{/descarga-pago\z})
      expect(run.id).to be_present
    end

    it "[REQ-FIT-AUTH-001] resolves show only with matching X-Workspace-Tab-Id" do
      project_a = start_workspace_for_tab!(tab_a)
      project_b = start_workspace_for_tab!(tab_b)

      get workshop_path, headers: tab_headers(tab_a)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("preview_zone_project_#{project_a.id}")

      get workshop_path, headers: tab_headers(tab_b)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("preview_zone_project_#{project_b.id}")
      expect(response.body).not_to include("preview_zone_project_#{project_a.id}")
    end
  end

  describe "missing tab identity [REQ-FIT-AUTH-001]" do
    it "[REQ-FIT-AUTH-001] redirects from workshop when tab cookie and header are absent (D21)" do
      project = start_workspace_for_tab!(tab_a)
      cookies.delete(ResolvesWorkspaceTab::TAB_COOKIE)

      get workshop_path

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
      expect(Project.exists?(project.id)).to be(true)
    end
  end

  describe "tab-close TTL [REQ-FIT-AUTH-001]" do
    it "[REQ-FIT-AUTH-001] expires project after 120s away with page closed message (D20)" do
      project = start_workspace_for_tab!(tab_a)
      cookies[Workspace::TabLeave::TAB_LEFT_COOKIE] = (121.seconds.ago.to_f * 1000).to_i

      get workshop_path, headers: tab_headers(tab_a)

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.tab_closed_expired"))
      expect(Project.exists?(project.id)).to be(false)
      expect(session.dig(Workspace::WORKSPACES_KEY, tab_a)).to be_nil
    end

    it "[REQ-FIT-AUTH-001] keeps project within 120s after closing the page (D20)" do
      project = start_workspace_for_tab!(tab_a)
      project.update!(last_activity_at: 10.minutes.ago)
      cookies[Workspace::TabLeave::TAB_LEFT_COOKIE] = (30.seconds.ago.to_f * 1000).to_i

      get workshop_path, headers: tab_headers(tab_a)

      expect(response).to have_http_status(:ok)
      expect(Project.exists?(project.id)).to be(true)
    end

    it "[REQ-FIT-AUTH-001] recovers project show when tab_id header missing but session still bound (D21)" do
      project = start_workspace_for_tab!(tab_a)
      cookies[ResolvesWorkspaceTab::TAB_COOKIE] = tab_a

      get workshop_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="project-show"')
      expect(response.body).to include("preview_zone_project_#{project.id}")
      expect(Project.exists?(project.id)).to be(true)
    end

    it "[REQ-FIT-AUTH-001] keeps project with no tab-left cookie regardless of last_activity_at (D20)" do
      project = start_workspace_for_tab!(tab_a)
      project.update!(last_activity_at: 10.minutes.ago)

      get workshop_path, headers: tab_headers(tab_a)

      expect(response).to have_http_status(:ok)
      expect(Project.exists?(project.id)).to be(true)
    end
  end
end
