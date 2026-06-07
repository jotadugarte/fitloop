# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::SimulatePlanPurchase, "[REQ-FIT-BILL-002]" do
  include BillingModelHelpers

  let(:user) { create_billing_user! }

  it "uses matching plan cart snapshots when currency_mode aligns" do
    Cart.create!(
      kind: "plan",
      tier_months: 2,
      user: user,
      currency_mode: "usd",
      overage: false,
      list_price_cents: 1150,
      sinpe_price_cents: 1075
    )

    result = described_class.call(
      user: user,
      tier_months: 2,
      payment_method: "card_usd",
      outcome: "success",
      project: nil
    )

    expect(result[:payment].amount).to eq(11.5)
    expect(result[:subscription].tier_months).to eq(2)
  end

  it "ignores cart rows when tier_months do not match" do
    Cart.create!(
      kind: "plan",
      tier_months: 1,
      user: user,
      currency_mode: "usd",
      overage: false,
      list_price_cents: 700,
      sinpe_price_cents: 650
    )

    result = described_class.call(
      user: user,
      tier_months: 2,
      payment_method: "card_usd",
      outcome: "success",
      project: nil
    )

    expect(result[:payment].amount).to eq(Billing::Pricing.plan_2_months_card_usd)
  end

  it "ignores cart rows when currency_mode does not match the payment method" do
    Cart.create!(
      kind: "plan",
      tier_months: 2,
      user: user,
      currency_mode: "crc",
      overage: false,
      list_price_cents: 5300,
      sinpe_price_cents: 5000
    )

    result = described_class.call(
      user: user,
      tier_months: 2,
      payment_method: "card_usd",
      outcome: "success",
      project: nil
    )

    expect(result[:payment].amount).to eq(Billing::Pricing.plan_2_months_card_usd)
  end
end
