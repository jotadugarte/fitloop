# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Paywall billing selection defaults", "[REQ-FIT-BILL-001]", type: :request do
  include BillingHelper
  describe "GET /taller/descarga-pago [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] exposes resolved billing selection (currency/method) in the HTML (D3, D16)" do
      begin_workspace_session!

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-billing-currency="crc"')
      expect(response.body).to include('data-billing-payment-method="sinpe"')
    end

    it "[REQ-FIT-BILL-001] renders a manual selector form that PATCHes workspace billing prefs (D3)" do
      begin_workspace_session!

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('action="/taller/workspace"')
      expect(response.body).to include('name="_method" value="patch"')
      expect(response.body).to include('name="section"')
      expect(response.body).to include('value="billing"')
      expect(response.body).to include('name="billing[currency]"')
      expect(response.body).to include('name="billing[payment_method]"')
      expect(response.body).not_to include(">Aplicar<")
      expect(response.body).not_to include('value="Apply"')
    end

    it "[REQ-FIT-BILL-001] does not offer SINPE in the selector when country != CR (D29)" do
      begin_workspace_session!

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "US" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('option value="sinpe"')
    end

    it "[REQ-FIT-BILL-001] shows plan tiers inline with add-to-cart CTAs (D25)" do
      begin_workspace_session!

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="paywall-plan-tier-1"')
      expect(response.body).to include('data-testid="paywall-plan-tier-2"')
      expect(response.body).to include('data-testid="paywall-plan-tier-4"')
      expect(response.body).to include('data-testid="paywall-add-plan-1"')
      expect(response.body).to include('data-testid="paywall-add-plan-2"')
      expect(response.body).to include('data-testid="paywall-add-plan-4"')
    end

    it "[REQ-FIT-BILL-001] displays single-download and plan prices on the paywall (D25)" do
      project = begin_workspace_session!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)

      get "/taller/descarga-pago", headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="paywall-single-download"')
      expect(response.body).to include(format_billing_crc(Billing::Pricing.single_download_sinpe_crc))
      expect(response.body).to include(format_billing_crc(Billing::Pricing.single_download_official_crc))
      expect(response.body).to include(format_billing_crc(Billing::Pricing.plan_1_month_sinpe_crc))
      expect(response.body).not_to include(format_billing_usd(Billing::Pricing.plan_1_month_card_usd))
      expect(run.id).to be_present
    end

    it "[REQ-FIT-BILL-001] reloads paywall when billing prefs change (no Apply button)" do
      project = begin_workspace_session!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)

      patch workspace_workshop_path,
            params: {
              section: "billing",
              billing_return_to: "paywall",
              billing: { currency: "usd", payment_method: "card" }
            }

      expect(response).to redirect_to("/taller/descarga-pago")
      follow_redirect!
      expect(response.body).to include('data-billing-currency="usd"')
      expect(response.body).to include(format_billing_usd(Billing::Pricing.single_download_official_usd))
      expect(run.id).to be_present
    end
  end
end

