# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout from cart", "[REQ-FIT-BILL-001]", type: :request do
  include BillingModelHelpers

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  it "[REQ-FIT-BILL-001] allows GET /checkout without nesting_run_id when cart has item (D1)" do
    user = create_billing_user!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)

    Cart.create!(
      kind: "single_download",
      nesting_run: run,
      currency_mode: "usd",
      overage: false,
      user: user,
      list_price_cents: 250,
      sinpe_price_cents: 200
    )

    sign_in_user! user
    get "/checkout", headers: { "CF-IPCountry" => "CR" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="checkout-page"')
  end
end

