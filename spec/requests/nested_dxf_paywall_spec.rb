# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nested DXF download paywall", "[REQ-FIT-BILL-001] [REQ-FIT-BILL-002]", type: :request do
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

  def paywall_path_for(project)
    "/taller/descarga-pago"
  end

  describe "GET /projects/:id/nested_dxf [REQ-FIT-BILL-001]" do
    context "without download entitlement" do
      it "[REQ-FIT-BILL-001] redirects signed-in user to paywall when no grant or plan (D42)" do
        user = create_billing_user!
        project = begin_workspace_session!
        attach_nested_output!(project)
        sign_in_user! user

        get nested_dxf_project_path(project)

        expect(response).to redirect_to(paywall_path_for(project))
      end

      it "[REQ-FIT-BILL-001] redirects guest to paywall (D40)" do
        project = begin_workspace_session!
        attach_nested_output!(project)

        get nested_dxf_project_path(project)

        expect(response).to redirect_to(paywall_path_for(project))
      end
    end

    context "with download entitlement" do
      it "[REQ-FIT-BILL-001] serves nested DXF when user has a single-purchase grant" do
        user = create_billing_user!
        project = begin_workspace_session!
        run = attach_nested_output!(project)
        DownloadGrant.create!(
          user: user,
          nesting_run: run,
          kind: "single_purchase",
          retained_until: 1.day.from_now
        )
        sign_in_user! user

        get nested_dxf_project_path(project)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("NESTED DXF CONTENT")
      end

      it "[REQ-FIT-BILL-002] serves nested DXF and consumes plan quota when user has active plan" do
        user = create_billing_user!
        create_active_subscription!(user: user)
        project = begin_workspace_session!
        attach_nested_output!(project)
        sign_in_user! user

        get nested_dxf_project_path(project)

        expect(response).to have_http_status(:ok)
        usage = PlanMonthlyUsage.find_by!(subscription: user.subscriptions.first)
        expect(usage.downloads_used).to eq(1)
      end

      it "[REQ-FIT-NEST-003] serves nested DXF when latest run is partial with orphans unresolved (D23)" do
        user = create_billing_user!
        create_active_subscription!(user: user)
        project = begin_workspace_session!
        project.nesting_runs.create!(status: "partial")
        project.update!(status: :partial)
        project.nested_dxf.attach(
          io: StringIO.new("PARTIAL NESTED DXF"),
          filename: "nested.dxf",
          content_type: "application/dxf"
        )
        sign_in_user! user

        get nested_dxf_project_path(project)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("PARTIAL NESTED DXF")
      end
    end
  end

  describe "preview remains free [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] allows project show and nesting sync without paywall" do
      user = create_billing_user!
      project = begin_workspace_session!
      attach_nested_output!(project)
      sign_in_user! user

      get project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="nesting-preview-panel"')

      get nesting_sync_project_path(project), headers: { "Accept" => "text/vnd.turbo-stream.html" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "email confirmation gate [REQ-FIT-BILL-002]" do
    let(:unconfirmed_user) do
      User.new(
        email: "pending@example.com",
        password: "securepassword12",
        password_confirmation: "securepassword12",
        name: "Pending User",
        terms_accepted_at: Time.current,
        terms_version: "v1-placeholder",
        time_zone: "America/Costa_Rica"
      ).tap(&:skip_confirmation_notification!).tap(&:save!)
    end

    it "[REQ-FIT-BILL-002] blocks nested DXF download for unconfirmed email (D22)" do
      project = begin_workspace_session!
      attach_nested_output!(project)
      sign_in_user! unconfirmed_user

      get nested_dxf_project_path(project)

      expect(response).to redirect_to(email_confirmation_pending_path)
    end
  end
end
