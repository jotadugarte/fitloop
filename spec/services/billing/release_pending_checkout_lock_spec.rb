# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::ReleasePendingCheckoutLock, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Release lock spec", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }

  def pending_sinpe_payment!(**attrs)
    Payment.create!(
      {
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_release_#{SecureRandom.hex(4)}",
        onvo_mode: "test",
        gateway_status: "processing",
        created_at: 5.minutes.ago
      }.merge(attrs)
    )
  end

  describe ".call [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] sets checkout_abandoned_at and checkout_lock_released_at without changing status" do
      payment = pending_sinpe_payment!

      described_class.call(payment: payment, user: user)

      payment.reload
      expect(payment).to be_pending
      expect(payment.checkout_abandoned_at).to be_present
      expect(payment.checkout_lock_released_at).to be_present
      expect(payment.checkout_lock_reason).to eq("user_abandoned")
    end

    it "[REQ-FIT-BILL-001] deactivates workshop lock after manual abandon" do
      payment = pending_sinpe_payment!

      described_class.call(payment: payment, user: user)

      expect(payment.reload.checkout_lock_active?).to be(false)
      expect(Billing::PendingCheckoutLock.new(payment: payment).active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] is idempotent when lock was already released" do
      payment = pending_sinpe_payment!(
        checkout_abandoned_at: 2.minutes.ago,
        checkout_lock_released_at: 2.minutes.ago,
        checkout_lock_reason: "user_abandoned"
      )
      abandoned_at = payment.checkout_abandoned_at

      described_class.call(payment: payment, user: user)

      payment.reload
      expect(payment).to be_pending
      expect(payment.checkout_abandoned_at).to eq(abandoned_at)
    end
  end
end
