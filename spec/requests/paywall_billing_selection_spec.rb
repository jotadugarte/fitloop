# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Paywall billing selection defaults", "[REQ-FIT-BILL-001]", type: :request do
  include BillingHelper

  describe "GET /taller/descarga-pago [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] creates a workshop bind when visiting paywall without prior workspace (D3)" do
      user = create_billing_user!
      sign_in_user_for_request!(user)

      expect(session[Workspace::SESSION_KEY]).to be_blank

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(session[Workspace::SESSION_KEY]).to be_present
      expect(Project.ephemeral.find_by(id: session[Workspace::SESSION_KEY])).to be_present
    end

    it "[REQ-FIT-BILL-001] exposes resolved billing currency in the HTML (D3, D16)" do
      begin_workspace_session!

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-billing-currency="crc"')
      expect(response.body).not_to include('data-testid="paywall-billing-selector"')
    end

    it "[REQ-FIT-BILL-001] does not offer SINPE selector on paywall (payment method is at checkout) (D29)" do
      begin_workspace_session!

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "US" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('name="billing[payment_method]"')
    end

    it "[REQ-FIT-BILL-001] shows plan tiers with continue-to-checkout CTAs (D25)" do
      begin_workspace_session!

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="paywall-plan-tier-1"')
      expect(response.body).to include(I18n.t("billing.paywall.continue_to_checkout"))
      expect(response.body).not_to include(I18n.t("billing.cart.add_to_cart"))
    end

    it "[REQ-FIT-BILL-001] displays single-download and plan prices on the paywall (D25)" do
      project = begin_workspace_session!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="paywall-single-download"')
      expect(response.body).to include(format_billing_crc(Billing::Pricing.single_download_sinpe_crc))
      expect(response.body).to include(format_billing_crc(Billing::Pricing.plan_1_month_sinpe_crc))
      expect(run.id).to be_present
    end

    it "[REQ-FIT-BILL-001] posts plan selection to cart and lands on checkout (D25)" do
      user = create_billing_user!
      project = begin_workspace_session!
      project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)
      sign_in_user_for_request!(user)

      post "/carrito",
           params: { kind: "plan", tier_months: 1 },
           headers: { "CF-IPCountry" => "CR" }

      expect(response).to redirect_to("/checkout")
      follow_redirect! headers: { "CF-IPCountry" => "CR" }
      expect(response.body).to include('data-testid="checkout-page"')
      expect(response.body).to include('data-testid="checkout-method-selector"')
      expect(response.body).to include('value="sinpe_crc"')
      expect(response.body).to include('value="card_crc"')
      expect(response.body).to include('data-testid="checkout-process-payment"')
    end

    def sign_in_user_for_request!(user)
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
    end
  end
end
