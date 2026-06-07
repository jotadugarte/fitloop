# frozen_string_literal: true

require "rails_helper"

RSpec.describe BillingHelper, "[REQ-FIT-BILL-001]", type: :helper do
  describe "#l_in_user_zone" do
    it "returns an empty string when time is blank" do
      expect(helper.l_in_user_zone(nil, format: :short, user: nil)).to eq("")
    end

    it "formats in the user's time zone when present" do
      user = instance_double(User, time_zone: "America/Costa_Rica")
      allow(user).to receive(:time_zone).and_return("America/Costa_Rica")
      time = Time.zone.parse("2026-06-06 12:00:00 UTC")

      formatted = helper.l_in_user_zone(time, format: :short, user: user)

      expect(formatted).to eq(I18n.l(time.in_time_zone("America/Costa_Rica"), format: :short))
    end

    it "falls back to the application time zone when the user has none" do
      user = instance_double(User, time_zone: nil)
      allow(user).to receive(:time_zone).and_return(nil)
      time = Time.zone.parse("2026-06-06 12:00:00 UTC")

      formatted = helper.l_in_user_zone(time, format: :short, user: user)

      expect(formatted).to eq(I18n.l(time.in_time_zone(Time.zone.name), format: :short))
    end
  end

  describe "#plan_tier_label" do
    it "maps supported tier months to i18n keys" do
      expect(helper.plan_tier_label(1)).to eq(I18n.t("billing.planes.tier_1"))
      expect(helper.plan_tier_label(2)).to eq(I18n.t("billing.planes.tier_2"))
      expect(helper.plan_tier_label(4)).to eq(I18n.t("billing.planes.tier_4"))
    end

    it "raises for unknown tier months" do
      expect { helper.plan_tier_label(3) }.to raise_error(ArgumentError, /unknown plan tier_months/)
    end
  end

  describe "#payment_status_badge_class" do
    it "returns the badge class for each payment status" do
      expect(helper.payment_status_badge_class("succeeded")).to eq("status-badge--completed")
      expect(helper.payment_status_badge_class("failed")).to eq("status-badge--failed")
      expect(helper.payment_status_badge_class("pending")).to eq("status-badge--draft")
    end
  end

  describe "#paywall_price_display" do
    it "formats single-download USD prices" do
      display = helper.paywall_price_display(product: :single_download, currency: :usd, show_sinpe: false)

      expect(display[:primary_amount]).to eq("$2.50")
      expect(display[:reference_amount]).to be_nil
    end

    it "formats single-download CRC prices with SINPE hero and card reference" do
      display = helper.paywall_price_display(product: :single_download, currency: :crc, show_sinpe: true)

      expect(display[:primary_amount]).to eq("₡1,000")
      expect(display[:reference_amount]).to eq("₡1,200")
    end

    it "formats single-download CRC prices without SINPE reference" do
      display = helper.paywall_price_display(product: :single_download, currency: :crc, show_sinpe: false)

      expect(display[:primary_amount]).to eq("₡1,200")
      expect(display[:reference_label]).to be_nil
      expect(display[:reference_amount]).to be_nil
    end

    it "formats plan USD prices" do
      display = helper.paywall_price_display(
        product: :plan,
        currency: :usd,
        show_sinpe: false,
        tier_months: 2
      )

      expect(display[:primary_amount]).to eq("$11.50")
      expect(display[:reference_amount]).to be_nil
    end

    it "formats plan CRC prices with SINPE hero and card reference" do
      display = helper.paywall_price_display(
        product: :plan,
        currency: :crc,
        show_sinpe: true,
        tier_months: 4
      )

      expect(display[:primary_amount]).to eq("₡8,000")
      expect(display[:reference_amount]).to eq("₡8,400")
    end

    it "formats plan CRC prices without SINPE reference" do
      display = helper.paywall_price_display(
        product: :plan,
        currency: :crc,
        show_sinpe: false,
        tier_months: 1
      )

      expect(display[:primary_amount]).to eq("₡3,250")
      expect(display[:reference_amount]).to be_nil
    end

    it "rejects unsupported products" do
      expect do
        helper.paywall_price_display(product: :mystery, currency: :usd, show_sinpe: false)
      end.to raise_error(ArgumentError, /unsupported product/)
    end
  end

  describe "amount formatting helpers" do
    it "formats USD and CRC amounts" do
      expect(helper.format_billing_usd(2.5)).to eq("$2.50")
      expect(helper.format_billing_crc(1200)).to eq("₡1,200")
      expect(helper.format_billing_crc(1200.5)).to eq("₡1,200.50")
    end

    it "routes format_billing_amount by currency" do
      expect(helper.format_billing_amount(2.5, :usd)).to eq("$2.50")
      expect(helper.format_billing_amount(1200, :crc)).to eq("₡1,200")
    end

    it "returns currency labels" do
      expect(helper.billing_currency_label(:usd)).to eq("USD")
      expect(helper.billing_currency_label(:crc)).to eq("CRC")
    end
  end
end
