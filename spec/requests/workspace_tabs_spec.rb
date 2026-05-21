# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workspace tab isolation", type: :request do
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
      start_workspace_for_tab!(tab_b)

      get project_path(project_a), headers: tab_headers(tab_a)
      expect(response).to have_http_status(:ok)

      get project_path(project_a), headers: tab_headers(tab_b)
      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
    end
  end

  describe "activity TTL [REQ-FIT-AUTH-001]" do
    it "[REQ-FIT-AUTH-001] expires project after 120s idle with explicit message (D20)" do
      project = start_workspace_for_tab!(tab_a)
      project.update!(last_activity_at: 121.seconds.ago)

      get project_path(project), headers: tab_headers(tab_a)

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.activity_expired"))
      expect(Project.exists?(project.id)).to be(false)
      expect(session.dig(Workspace::WORKSPACES_KEY, tab_a)).to be_nil
    end

    it "[REQ-FIT-AUTH-001] keeps project within 120s idle (D20)" do
      project = start_workspace_for_tab!(tab_a)
      project.update!(last_activity_at: 30.seconds.ago)

      get project_path(project), headers: tab_headers(tab_a)

      expect(response).to have_http_status(:ok)
      expect(Project.exists?(project.id)).to be(true)
    end
  end
end
