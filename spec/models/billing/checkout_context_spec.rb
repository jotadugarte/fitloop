# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CheckoutContext, "[REQ-FIT-BILL-001]" do
  describe ".from_session" do
    it "builds from a billing_context hash" do
      ctx = described_class.from_session(
        currency: :crc,
        payment_method: :sinpe,
        iva_applicable: true,
        country_code: "CR"
      )

      expect(ctx.currency.to_sym).to eq(:crc)
      expect(ctx.payment_method.to_sym).to eq(:sinpe)
      expect(ctx.iva_applicable).to be(true)
      expect(ctx.country_code.to_s).to eq("CR")
    end

    it "rejects sinpe with USD" do
      expect do
        described_class.new(currency: :usd, payment_method: :sinpe, iva_applicable: false)
      end.to raise_error(ArgumentError, /incompatible/)
    end

    it "rejects IVA outside Costa Rica when country is explicit" do
      expect do
        described_class.new(
          currency: :usd,
          payment_method: :card,
          country_code: Billing::CountryCode.parse("US"),
          iva_applicable: true
        )
      end.to raise_error(ArgumentError, /IVA/)
    end
  end

  describe "#to_h" do
    it "round-trips session-compatible keys" do
      ctx = described_class.from_session(currency: :usd, payment_method: :card, iva_applicable: false)
      expect(ctx.to_h).to eq(currency: :usd, payment_method: :card, country_code: nil, iva_applicable: false)
    end
  end
end
