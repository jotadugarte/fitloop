# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CartTotals, "[REQ-FIT-BILL-001]" do
  include BillingModelHelpers

  describe ".for_cart [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] returns list subtotal cents for cart review (D25)" do
      cart = Cart.create!(
        kind: "single_download",
        nesting_run: create_nesting_run!,
        currency_mode: "usd",
        overage: false,
        guest_token: "guest-1",
        list_price_cents: 250,
        sinpe_price_cents: 200
      )

      totals = described_class.for_cart(cart)

      expect(totals.fetch(:list_subtotal_cents)).to eq(250)
    end
  end
end

