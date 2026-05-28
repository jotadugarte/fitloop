# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout method-first flow", "[REQ-FIT-BILL-001] [REQ-FIT-BILL-002]", type: :request do
  include BillingModelHelpers

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def create_single_download_cart!(user:, run:)
    Cart.create!(
      kind: "single_download",
      nesting_run: run,
      currency_mode: "crc",
      overage: false,
      user: user,
      list_price_cents: 1200,
      sinpe_price_cents: 1000
    )
  end

  it "[REQ-FIT-BILL-001] renders payment method selector before the receipt breakdown (D37)" do
    user = create_billing_user!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    create_single_download_cart!(user: user, run: run)

    sign_in_user! user
    get checkout_path, headers: { "CF-IPCountry" => "CR" }

    expect(response).to have_http_status(:ok)
    body = response.body

    expect(body).to include('data-testid="checkout-method-title"')
    expect(body).to include('data-testid="checkout-breakdown"')

    expect(body.index('data-testid="checkout-method-title"')).to be < body.index('data-testid="checkout-breakdown"')
  end

  it "[REQ-FIT-BILL-001] updates receipt amounts based on selected payment method (SINPE vs card) (D25, D37)" do
    user = create_billing_user!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    create_single_download_cart!(user: user, run: run)

    sign_in_user! user

    get checkout_path(payment_method: "sinpe_crc"), headers: { "CF-IPCountry" => "CR" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="breakdown-sinpe-discount"')

    get checkout_path(payment_method: "card_crc"), headers: { "CF-IPCountry" => "CR" }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('data-testid="breakdown-sinpe-discount"')
  end

  it "[REQ-FIT-BILL-001] exposes a single final CTA to process payment (D37)" do
    user = create_billing_user!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    create_single_download_cart!(user: user, run: run)

    sign_in_user! user
    get checkout_path, headers: { "CF-IPCountry" => "CR" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="checkout-process-payment"')
    expect(response.body).not_to include('data-testid="checkout-pay-card-usd"')
  end
end

