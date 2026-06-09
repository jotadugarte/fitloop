# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Billing preferences in workspace", "[REQ-FIT-BILL-001]", type: :request do
  describe "PATCH /taller/workspace?section=billing [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] persists payment method and forces country currency in session (D3)" do
      begin_workspace_session!

      patch workspace_workshop_path,
            params: { section: "billing", billing: { payment_method: "card" } },
            headers: { "Accept" => "text/vnd.turbo-stream.html", "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(session[:billing_currency]).to eq("crc")
      expect(session[:billing_payment_method]).to eq("card")
    end

    it "[REQ-FIT-BILL-001] falls back to the default payment method when an unsupported value is posted" do
      begin_workspace_session!

      patch workspace_workshop_path,
            params: { section: "billing", billing: { payment_method: "bitcoin" } },
            headers: { "CF-IPCountry" => "US" }

      expect(response).to have_http_status(:ok)
      expect(session[:billing_payment_method]).to eq("card")
    end

    it "[REQ-FIT-BILL-001] redirects back to the paywall when billing_return_to is paywall" do
      begin_workspace_session!

      patch workspace_workshop_path,
            params: {
              section: "billing",
              billing: { payment_method: "card" },
              billing_return_to: "paywall"
            },
            headers: { "CF-IPCountry" => "US" }

      expect(response).to redirect_to(download_paywall_workshop_path)
    end

    it "[REQ-FIT-BILL-001] returns unprocessable entity when billing params are missing" do
      begin_workspace_session!

      patch workspace_workshop_path, params: { section: "billing" }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
