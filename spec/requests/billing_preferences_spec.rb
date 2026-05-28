# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Billing preferences in workspace", "[REQ-FIT-BILL-001]", type: :request do
  describe "PATCH /taller/workspace?section=billing [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] persists manual currency/method selection in session (D3)" do
      begin_workspace_session!

      patch workshop_workspace_path,
            params: { section: "billing", billing: { currency: "usd", payment_method: "card" } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(session[:billing_currency]).to eq("usd")
      expect(session[:billing_payment_method]).to eq("card")
    end
  end
end

