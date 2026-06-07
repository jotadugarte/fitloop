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

  describe ".for_cart [REQ-FIT-BILL-001]" do
    it "raises when cart is nil" do
      ctx = Billing::CheckoutContext.from_session(currency: :crc, payment_method: :sinpe, iva_applicable: true, country_code: "CR")

      expect { described_class.for_cart(cart: nil, billing_context: ctx) }
        .to raise_error(ArgumentError, /cart required/)
    end

    it "converts USD cart cents to major units" do
      cart = Cart.new(
        list_price_cents: 250,
        sinpe_price_cents: 250,
        currency_mode: "usd"
      )
      ctx = Billing::CheckoutContext.from_session(currency: :usd, payment_method: :card, iva_applicable: false, country_code: "US")

      breakdown = described_class.for_cart(cart: cart, billing_context: ctx)

      expect(breakdown.fetch(:list_price)).to eq(2.5)
    end
  end

  describe ".for_plan [REQ-FIT-BILL-001]" do
    it "accepts a TierMonths value object directly" do
      tier = Billing::TierMonths.parse(1)
      ctx = Billing::CheckoutContext.from_session(currency: :crc, payment_method: :sinpe, iva_applicable: true, country_code: "CR")

      breakdown = described_class.for_plan(tier_months: tier, billing_context: ctx)

      expect(breakdown.fetch(:total_amount)).to be > 0
    end
  end

  describe "card checkout without SINPE reference [REQ-FIT-BILL-001]" do
    it "omits SINPE discount for USD card payments" do
      breakdown = described_class.for_single_download(
        billing_context: { currency: :usd, payment_method: :card, iva_applicable: false },
        overage: false
      )

      expect(breakdown.fetch(:discount_amount)).to eq(0)
    end
  end

  describe "typed CheckoutContext [REQ-FIT-BILL-001]" do
    it "accepts CheckoutContext and returns unchanged hash shape" do
      ctx = Billing::CheckoutContext.from_session(
        currency: :crc,
        payment_method: :sinpe,
        iva_applicable: true,
        country_code: "CR"
      )
      breakdown = described_class.for_single_download(billing_context: ctx, overage: false)

      expect(breakdown.keys).to contain_exactly(
        :currency, :payment_method, :iva_applicable, :list_price,
        :discount_amount, :subtotal, :tax_amount, :total_amount
      )
      expect(breakdown.fetch(:total_amount)).to eq(1130)
    end
  end
end
