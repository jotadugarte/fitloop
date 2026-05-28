# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CartTotals, "[REQ-FIT-BILL-001]" do
  include BillingModelHelpers

  describe ".for_cart [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] returns list subtotal cents and regional breakdown (D25)" do
      cart = Cart.create!(
        kind: "single_download",
        nesting_run: create_nesting_run!,
        currency_mode: "crc",
        overage: false,
        guest_token: "guest-1",
        list_price_cents: 1200,
        sinpe_price_cents: 1000
      )
      billing_context = { currency: :crc, payment_method: :sinpe, iva_applicable: true }

      totals = described_class.for_cart(cart: cart, billing_context: billing_context)

      expect(totals.fetch(:list_subtotal_cents)).to eq(1200)
      expect(totals.fetch(:breakdown).fetch(:tax_amount)).to eq(130)
    end
  end
end
