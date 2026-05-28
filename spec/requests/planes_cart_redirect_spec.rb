# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Planes redirect when cart has item", "[REQ-FIT-BILL-001]", type: :request do
  include BillingModelHelpers

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /planes [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] redirects to /carrito when a cart item exists (D12)" do
      user = create_billing_user!
      begin_workspace_session!
      project = Project.ephemeral.order(:id).last!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)

      post "/carrito", params: { kind: "single_download", nesting_run_id: run.id, currency_mode: "usd" }

      sign_in_user! user
      get "/planes"

      expect(response).to redirect_to("/carrito")
    end
  end
end

