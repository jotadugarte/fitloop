# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout overage pricing display", "[REQ-FIT-BILL-001]", type: :request do
  include BillingModelHelpers

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  it "[REQ-FIT-BILL-001] shows explicit overage prices only when user has plan and quota is exhausted (D28)" do
    user = create_billing_user!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)

    subscription = create_active_subscription!(user: user, tier_months: 1)
    usage = Billing::QuotaCounter.for(subscription).usage
    usage.update!(downloads_used: usage.quota_limit)

    sign_in_user! user
    get checkout_path(nesting_run_id: run.id), headers: { "CF-IPCountry" => "CR" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="checkout-overage-pricing"')
    expect(response.body).to include(Billing::Pricing.single_download_overage_sinpe_crc.to_s)
    expect(response.body).to include(Billing::Pricing.single_download_overage_official_crc.to_s)
  end

  it "[REQ-FIT-BILL-001] hides overage prices when no exhausted plan exists (D28)" do
    user = create_billing_user!(email: "no-overage@example.com")
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)

    sign_in_user! user
    get checkout_path(nesting_run_id: run.id), headers: { "CF-IPCountry" => "CR" }

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('data-testid="checkout-overage-pricing"')
  end
end

