# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::MoneyMinorUnits, "[REQ-FIT-BILL-001]" do
  describe ".from_breakdown [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] converts CRC CheckoutBreakdown total (colones) to ONVO minor units (centavos)" do
      breakdown = Billing::CheckoutBreakdown.for_single_download(
        billing_context: { currency: :crc, payment_method: :sinpe, iva_applicable: true },
        overage: false
      )

      minor = described_class.from_breakdown(breakdown)

      expect(minor.to_i).to eq(113_000)
      expect(minor.currency_code).to eq("CRC")
    end

    it "[REQ-FIT-BILL-001] converts USD CheckoutBreakdown total (dollars) to ONVO minor units (cents)" do
      breakdown = Billing::CheckoutBreakdown.for_single_download(
        billing_context: { currency: :usd, payment_method: :card, iva_applicable: false },
        overage: false
      )

      minor = described_class.from_breakdown(breakdown)

      expect(minor.to_i).to eq((breakdown.fetch(:total_amount) * 100).round)
      expect(minor.currency_code).to eq("USD")
    end

    it "[REQ-FIT-BILL-001] rounds USD fractional cents to nearest integer minor unit" do
      breakdown = { currency: :usd, total_amount: BigDecimal("10.555") }

      minor = described_class.from_breakdown(breakdown)

      expect(minor.to_i).to eq(1056)
    end

    it "[REQ-FIT-BILL-001] rejects unsupported currency" do
      expect do
        described_class.from_breakdown(currency: :eur, total_amount: 10)
      end.to raise_error(ArgumentError, /unsupported currency/)
    end
  end
end
