# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nested DXF re-download rules", "[REQ-FIT-BILL-002] [REQ-FIT-BILL-003]", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def attach_nested_output!(project)
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF CONTENT"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    run
  end

  def complete_single_purchase!(user:, project:)
    run = attach_nested_output!(project)
    sign_in_user! user
    post checkout_simulate_path,
         params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
    DownloadGrant.find_by!(user: user, nesting_run: run)
  end

  describe "plan downloads require live workshop project [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] blocks download when workshop tab-close TTL expired despite active plan (D50)" do
      user = create_billing_user!
      project = begin_workspace_session!
      attach_nested_output!(project)
      create_active_subscription!(user: user)
      sign_in_user! user
      cookies[Workspace::TabLeave::TAB_LEFT_COOKIE] = (121.seconds.ago.to_f * 1000).to_i

      get nested_dxf_project_path(project)

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.tab_closed_expired"))
    end

    it "[REQ-FIT-BILL-002] blocks download after workspace discard even with plan_included grant (D50)" do
      user = create_billing_user!
      project = begin_workspace_session!
      run = attach_nested_output!(project)
      create_active_subscription!(user: user)
      DownloadGrant.create!(user: user, nesting_run: run, kind: "plan_included")
      sign_in_user! user
      project_id = project.id
      Workspace.discard!(session)

      get "/projects/#{project_id}/nested_dxf"

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("NESTED DXF CONTENT")
    end

    it "[REQ-FIT-BILL-002] allows plan download while project remains bound with quota (D50)" do
      user = create_billing_user!
      project = begin_workspace_session!
      attach_nested_output!(project)
      create_active_subscription!(user: user)
      sign_in_user! user

      get nested_dxf_project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("NESTED DXF CONTENT")
    end
  end

  describe "single purchase from project route [REQ-FIT-BILL-003]" do
    it "[REQ-FIT-BILL-003] serves nested DXF from project while grant is valid and project is bound (D54)" do
      user = create_billing_user!
      project = begin_workspace_session!
      complete_single_purchase!(user: user, project: project)

      get nested_dxf_project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("NESTED DXF CONTENT")
    end

    it "[REQ-FIT-BILL-003] blocks project-route download after workspace discard (D54)" do
      user = create_billing_user!
      project = begin_workspace_session!
      complete_single_purchase!(user: user, project: project)
      project_id = project.id
      Workspace.discard!(session)

      get "/projects/#{project_id}/nested_dxf"

      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to include("NESTED DXF CONTENT")
    end
  end
end
