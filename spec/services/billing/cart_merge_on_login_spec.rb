# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CartMergeOnLogin, "[REQ-FIT-BILL-001]" do
  include BillingModelHelpers

  describe ".call [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] keeps user cart and discards guest cart when both exist (D15)" do
      user = create_billing_user!

      guest_cart = Cart.create!(
        kind: "plan",
        tier_months: 1,
        currency_mode: "usd",
        overage: false,
        guest_token: "guest-123",
        list_price_cents: 700,
        sinpe_price_cents: 650
      )

      user_cart = Cart.create!(
        kind: "plan",
        tier_months: 2,
        currency_mode: "usd",
        overage: false,
        user: user,
        list_price_cents: 1150,
        sinpe_price_cents: 1050
      )

      described_class.call(user: user, guest_token: "guest-123")

      expect(Cart.exists?(guest_cart.id)).to eq(false)
      expect(Cart.exists?(user_cart.id)).to eq(true)
    end
  end
end

