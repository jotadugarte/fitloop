# frozen_string_literal: true

require "rails_helper"

RSpec.describe Cart, "[REQ-FIT-BILL-001] [REQ-FIT-BILL-002]" do
  it "[REQ-FIT-BILL-001] supports single-item carts stored in DB (D6)" do
    expect(described_class).to be < ApplicationRecord
  end

  describe "invariants [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] requires either guest_token or user (D6)" do
      cart = described_class.new(
        kind: "single_download",
        currency_mode: "usd",
        list_price_cents: 250,
        sinpe_price_cents: 200,
        nesting_run: nil,
        tier_months: 1,
        guest_token: nil,
        user: nil
      )

      expect(cart).not_to be_valid
    end

    it "[REQ-FIT-BILL-001] requires exactly one of nesting_run or tier_months (D6)" do
      user = create_billing_user!

      cart_both = described_class.new(
        kind: "single_download",
        currency_mode: "usd",
        list_price_cents: 250,
        sinpe_price_cents: 200,
        nesting_run: NestingRun.new,
        tier_months: 1,
        user: user
      )
      expect(cart_both).not_to be_valid

      cart_neither = described_class.new(
        kind: "single_download",
        currency_mode: "usd",
        list_price_cents: 250,
        sinpe_price_cents: 200,
        nesting_run: nil,
        tier_months: nil,
        user: user
      )
      expect(cart_neither).not_to be_valid
    end
  end
end

