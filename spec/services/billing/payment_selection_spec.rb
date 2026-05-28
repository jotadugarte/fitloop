# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PaymentSelection, "[REQ-FIT-BILL-001]" do
  describe ".resolve [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] prefers manual session override over geo defaults (D3, D16)" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      session = { billing_currency: "usd", billing_payment_method: "card" }

      selection = described_class.resolve(request: request, session: session)

      expect(selection.fetch(:currency)).to eq(:usd)
      expect(selection.fetch(:payment_method)).to eq(:card)
    end

    it "[REQ-FIT-BILL-001] falls back to GeoPaymentDefaults when no manual override (D16)" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      session = {}

      selection = described_class.resolve(request: request, session: session)

      expect(selection.fetch(:currency)).to eq(:crc)
      expect(selection.fetch(:payment_method)).to eq(:sinpe)
    end
  end
end

