# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Single download checkout with active plan quota", "[REQ-FIT-BILL-002]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def prepare_single_download!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF CONTENT"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    { project: project, run: run }
  end

  let(:user) { create_billing_user! }
  let!(:checkout_context) { prepare_single_download! }
  let(:project) { checkout_context[:project] }
  let(:run) { checkout_context[:run] }

  before do
    create_active_subscription!(user: user)
    sign_in_user! user
  end

  describe "GET /checkout [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] redirects to project when plan monthly quota is available (D33)" do
      get checkout_path(nesting_run_id: run.id)

      expect(response).to redirect_to(project_path(project))
      follow_redirect!
      expect(response.body).to include(I18n.t("billing.checkout.plan_quota_prioritized"))
    end
  end

  describe "POST /checkout/simular [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] does not record payment when plan monthly quota is available" do
      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
      end.not_to change(Payment, :count)

      expect(response).to redirect_to(project_path(project))
    end
  end
end
