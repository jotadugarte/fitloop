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

      expect(response).to redirect_to("/checkout")
    end

    it "[REQ-FIT-BILL-001] does not redirect when only another user's cart exists (D12)" do
      other_user = create_billing_user!(email: "other-cart@example.com")
      user = create_billing_user!(email: "viewer@example.com")
      project = begin_workspace_session!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)

      Cart.create!(
        kind: "single_download",
        nesting_run: run,
        currency_mode: "crc",
        overage: false,
        user: other_user,
        list_price_cents: 1200,
        sinpe_price_cents: 1000
      )

      sign_in_user! user
      get "/planes"

      expect(response).to have_http_status(:ok)
      expect(response).not_to redirect_to("/checkout")
    end
  end
end
