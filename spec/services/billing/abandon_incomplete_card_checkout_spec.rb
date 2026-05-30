# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::AbandonIncompleteCardCheckout, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }

  def card_payment!(**attrs)
    Payment.create!(
      {
        user: user,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_abandon_#{SecureRandom.hex(4)}",
        onvo_mode: "test",
        gateway_status: "requires_payment_method"
      }.merge(attrs)
    )
  end

  describe ".call [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] marks card checkout abandoned without failing payment" do
      payment = card_payment!

      described_class.call(payment: payment)

      payment.reload
      expect(payment).to be_pending
      expect(payment).not_to be_failed
      expect(payment.checkout_abandoned_at).to be_present
      expect(payment.checkout_lock_reason).to eq("user_canceled_3ds")
    end

    it "[REQ-FIT-BILL-001] is idempotent when already abandoned" do
      payment = card_payment!(checkout_abandoned_at: 1.minute.ago, checkout_lock_reason: "user_canceled_3ds")

      expect(described_class.call(payment: payment)).to eq(:already_abandoned)
      expect(payment.reload).to be_pending
    end

    it "[REQ-FIT-BILL-001] does not abandon SINPE payments" do
      payment = Payment.create!(
        user: user,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_sinpe_abandon",
        onvo_mode: "test",
        gateway_status: "requires_payment_method"
      )

      expect(described_class.call(payment: payment)).to eq(:not_card)
      expect(payment.reload.checkout_abandoned_at).to be_nil
    end
  end
end
