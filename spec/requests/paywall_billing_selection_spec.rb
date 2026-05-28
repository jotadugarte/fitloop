# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Paywall billing selection defaults", "[REQ-FIT-BILL-001]", type: :request do
  describe "GET /taller/descarga-pago [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] exposes resolved billing selection (currency/method) in the HTML (D3, D16)" do
      project = begin_workspace_session!
      allow_any_instance_of(DownloadPaywallController).to receive(:request).and_return(
        instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      )

      get "/taller/descarga-pago"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-billing-currency="crc"')
      expect(response.body).to include('data-billing-payment-method="sinpe"')
    end
  end
end

