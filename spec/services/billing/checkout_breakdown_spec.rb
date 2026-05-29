# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CheckoutBreakdown, "[REQ-FIT-BILL-001]" do
  describe ".for_single_download [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] applies 13% IVA on net subtotal in CR with SINPE discount" do
      breakdown = described_class.for_single_download(
        billing_context: { currency: :crc, payment_method: :sinpe, iva_applicable: true },
        overage: false
      )

      expect(breakdown.fetch(:subtotal)).to eq(1000)
      expect(breakdown.fetch(:tax_amount)).to eq(130)
      expect(breakdown.fetch(:total_amount)).to eq(1130)
    end

    it "[REQ-FIT-BILL-001] omits IVA for international USD checkout" do
      breakdown = described_class.for_single_download(
        billing_context: { currency: :usd, payment_method: :card, iva_applicable: false },
        overage: false
      )

      expect(breakdown.fetch(:iva_applicable)).to be(false)
      expect(breakdown.fetch(:tax_amount)).to eq(0)
      expect(breakdown.fetch(:total_amount)).to eq(breakdown.fetch(:subtotal))
    end
  end
end
