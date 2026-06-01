# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::VentasFilter, "[REQ-FIT-ADMIN-001]", type: :service do
  include ActiveSupport::Testing::TimeHelpers

  describe "#apply" do
    it "defaults to current month when date params are absent" do
      cr_now = Time.find_zone("America/Costa_Rica").now
      filter = described_class.new({})
      expect(filter.start_date_value).to eq(cr_now.beginning_of_month.to_date.to_s)
      expect(filter.end_date_value).to eq(cr_now.end_of_month.to_date.to_s)
    end

    it "escapes ILIKE wildcards in search terms" do
      user = create_billing_user!(email: "wildcard@example.com")
      Payment.create!(
        user: user, status: "succeeded", payment_method: "card_crc", currency: "crc",
        amount: 100, subtotal: 100, total_amount: 100, paid_at: Time.current,
        purchaser_name: "Wildcard Test", gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_w", onvo_mode: "test", gateway_status: "succeeded",
        purpose: "single_download"
      )

      filter = described_class.new({ search: "%" })
      expect(filter.apply(Payment.all)).to be_empty
    end

    it "allows open-ended ranges when an empty date param is submitted" do
      user = create_billing_user!(email: "filter@example.com")
      Payment.create!(
        user: user, status: "succeeded", payment_method: "card_crc", currency: "crc",
        amount: 100, subtotal: 100, total_amount: 100, paid_at: 5.days.ago,
        created_at: 5.days.ago, gateway_provider: "onvo", onvo_payment_intent_id: "pi_f",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )

      filter = described_class.new({ start_date: 2.days.ago.to_date.to_s, end_date: "" })
      scope = filter.apply(Payment.all)

      expect(scope).to be_empty
    end

    it "includes payments on the last CR calendar day when UTC is already the next month" do
      cr_zone = Time.find_zone("America/Costa_Rica")
      travel_to cr_zone.parse("2026-05-31 20:00:00") do
        user = create_billing_user!(email: "cr-boundary@example.com")
        payment = Payment.create!(
          user: user, status: "succeeded", payment_method: "card_crc", currency: "crc",
          amount: 100, subtotal: 100, total_amount: 100, paid_at: Time.current,
          created_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_cr",
          onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
        )

        filter = described_class.new({})
        expect(filter.apply(Payment.all)).to include(payment)
      end
    end
  end

  describe "#apply with date_column: :paid_at" do
    it "filters by paid_at in CR timezone, not created_at" do
      cr_zone = Time.find_zone("America/Costa_Rica")
      user = create_billing_user!(email: "paid-at-filter@example.com")

      paid_recently = Payment.create!(
        user: user, status: "succeeded", payment_method: "card_crc", currency: "crc",
        amount: 100, subtotal: 100, total_amount: 100,
        paid_at: cr_zone.parse("2026-05-15 10:00:00"),
        created_at: cr_zone.parse("2026-04-01 10:00:00"),
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_paid_recent",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )
      paid_old = Payment.create!(
        user: user, status: "succeeded", payment_method: "card_crc", currency: "crc",
        amount: 200, subtotal: 200, total_amount: 200,
        paid_at: cr_zone.parse("2026-04-10 10:00:00"),
        created_at: cr_zone.parse("2026-05-15 10:00:00"),
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_paid_old",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )

      filter = described_class.new(
        { start_date: "2026-05-01", end_date: "2026-05-31" },
        date_column: :paid_at
      )
      scope = filter.apply(Payment.all)

      expect(scope).to include(paid_recently)
      expect(scope).not_to include(paid_old)
    end

    it "excludes payments with NULL paid_at when a date range is applied" do
      user = create_billing_user!(email: "null-paid-at@example.com")
      pending = Payment.create!(
        user: user, status: "pending", payment_method: "card_crc", currency: "crc",
        amount: 100, subtotal: 100, total_amount: 100, paid_at: nil,
        created_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_null",
        onvo_mode: "test", gateway_status: "processing", purpose: "single_download"
      )

      filter = described_class.new(
        { start_date: Time.current.to_date.to_s, end_date: Time.current.to_date.to_s },
        date_column: :paid_at
      )

      expect(filter.apply(Payment.all)).not_to include(pending)
    end

    it "period_start_date and period_end_date fall back to current month when params are blank strings" do
      cr_zone = Time.find_zone("America/Costa_Rica")
      filter = described_class.new({ start_date: "", end_date: "" }, date_column: :paid_at)

      expect(filter.period_start_date).to eq(cr_zone.now.beginning_of_month.to_date.to_s)
      expect(filter.period_end_date).to eq(cr_zone.now.end_of_month.to_date.to_s)
    end

    it "form150_period_label reports unbounded range when date params are cleared" do
      filter = described_class.new({ start_date: "", end_date: "" }, date_column: :paid_at)

      expect(filter.form150_period_unbounded?).to be(true)
      expect(filter.form150_period_label).to eq("Sin filtro de fechas")
    end

    it "form150_period_label shows em dash when only one date bound is cleared" do
      filter = described_class.new({ start_date: "", end_date: "2026-05-31" }, date_column: :paid_at)

      expect(filter.form150_period_partial?).to be(true)
      expect(filter.form150_timestamp_filename?).to be(true)
      expect(filter.form150_period_label).to eq("— — 2026-05-31")
    end
  end

  describe ".normalize_form150_export_params" do
    it "defaults status to succeeded when omitted" do
      expect(described_class.normalize_form150_export_params({})).to include("status" => [ "succeeded" ])
    end

    it "preserves status when present with symbol key" do
      params = { status: [ "failed" ] }
      expect(described_class.normalize_form150_export_params(params)).to eq("status" => [ "failed" ])
    end

    it "defaults status to succeeded when status is an empty array" do
      expect(described_class.normalize_form150_export_params({ status: [] })).to include("status" => [ "succeeded" ])
    end
  end

  describe "#initialize" do
    it "coerces string-key params for indifferent date access" do
      filter = described_class.new({ "start_date" => "", "end_date" => "" }, date_column: :paid_at)

      expect(filter.form150_period_unbounded?).to be(true)
    end
  end
end
