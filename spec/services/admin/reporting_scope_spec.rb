# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ReportingScope, "[REQ-FIT-ADMIN-001]", type: :service do
  describe ".call" do
    it "excludes superseded payments" do
      user = create_billing_user!(email: "scope@example.com")
      active = Payment.create!(
        user: user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
        amount: 1000, subtotal: 1000, total_amount: 1130, paid_at: Time.current,
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_active",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )
      Payment.create!(
        user: user, status: "pending", payment_method: "sinpe_crc", currency: "crc",
        amount: 1000, subtotal: 1000, total_amount: 1130,
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_super",
        onvo_mode: "test", gateway_status: "processing", purpose: "single_download",
        superseded_at: Time.current, checkout_lock_reason: Billing::CheckoutLockReason::SUPERSEDED
      )

      expect(described_class.call).to contain_exactly(active)
    end
  end
end
