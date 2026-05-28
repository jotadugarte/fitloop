# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Paywall billing selection defaults", "[REQ-FIT-BILL-001]", type: :request do
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
  end
end

