# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::VentasListing, "[REQ-FIT-ADMIN-001]", type: :service do
  describe ".call" do
    it "paginates and orders by created_at" do
      user = create_billing_user!(email: "listing@example.com")
      older = Payment.create!(
        user: user, status: "succeeded", payment_method: "card_crc", currency: "crc",
        amount: 100, subtotal: 100, total_amount: 100, paid_at: 2.days.ago,
        created_at: 2.days.ago, gateway_provider: "onvo", onvo_payment_intent_id: "pi_old",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )
      newer = Payment.create!(
        user: user, status: "succeeded", payment_method: "card_crc", currency: "crc",
        amount: 200, subtotal: 200, total_amount: 200, paid_at: Time.current,
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_new",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )

      listing = described_class.call(Payment.where(currency: "crc"), direction: "desc", page: 1)

      expect(listing.payments.first.id).to eq(newer.id)
      expect(listing.payments.last.id).to eq(older.id)
      expect(listing.total_count).to eq(2)
    end
  end
end
