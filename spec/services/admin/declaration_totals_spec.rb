# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::DeclarationTotals, "[REQ-FIT-ADMIN-001]", type: :service do
  describe ".for_scope" do
    it "sums succeeded payments separately for CRC and USD" do
      user = create_billing_user!(email: "totals@example.com")
      Payment.create!(
        user: user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
        amount: 1000, list_price: 1000, subtotal: 1000, tax_amount: 130, total_amount: 1130,
        paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_crc_t",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )
      Payment.create!(
        user: user, status: "succeeded", payment_method: "card_usd", currency: "usd",
        amount: 5, list_price: 5, subtotal: 5, tax_amount: 0, total_amount: 5,
        paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_usd_t",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download",
        purchase_reference: "111111111111"
      )
      Payment.create!(
        user: user, status: "failed", payment_method: "sinpe_crc", currency: "crc",
        amount: 999, subtotal: 999, total_amount: 999,
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_fail_t",
        onvo_mode: "test", gateway_status: "failed", purpose: "single_download"
      )

      totals = described_class.for_scope(Payment.all)

      expect(totals.fetch(:crc).count).to eq(1)
      expect(totals.fetch(:crc).total).to eq(1130.0)
      expect(totals.fetch(:usd).count).to eq(1)
      expect(totals.fetch(:usd).total).to eq(5.0)
    end
  end
end
