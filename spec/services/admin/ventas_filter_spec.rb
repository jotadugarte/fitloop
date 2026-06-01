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

      filter = described_class.new(search: "%")
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

      filter = described_class.new(start_date: 2.days.ago.to_date.to_s, end_date: "")
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
end
