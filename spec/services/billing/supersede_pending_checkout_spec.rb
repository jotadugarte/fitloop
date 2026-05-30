# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::SupersedePendingCheckout, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Supersede spec", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }
  let(:other_run) { project.nesting_runs.create!(status: "completed") }

  def pending_sinpe_payment!(nesting_run: run, **attrs)
    Payment.create!(
      {
        user: user,
        nesting_run: nesting_run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_supersede_#{SecureRandom.hex(4)}",
        onvo_mode: "test",
        gateway_status: "processing",
        created_at: 10.minutes.ago
      }.merge(attrs)
    )
  end

  describe ".call [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] marks existing pending single-download payments for the same run as superseded and releases lock" do
      existing = pending_sinpe_payment!(created_at: 10.minutes.ago, onvo_payment_intent_id: "pi_existing")

      described_class.call(user: user, nesting_run: run)

      existing.reload
      expect(existing.superseded_at).to be_present
      expect(existing.checkout_lock_released_at).to be_present
      expect(existing.checkout_lock_reason).to eq("superseded")
      expect(existing).to be_pending
      expect(existing.checkout_lock_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] supersedes every pending sinpe attempt for the run before a replacement checkout" do
      first = pending_sinpe_payment!(created_at: 30.minutes.ago, onvo_payment_intent_id: "pi_first")
      second = pending_sinpe_payment!(created_at: 20.minutes.ago, onvo_payment_intent_id: "pi_second")

      described_class.call(user: user, nesting_run: run)

      expect(first.reload.superseded_at).to be_present
      expect(second.reload.superseded_at).to be_present
    end

    it "[REQ-FIT-BILL-001] does not supersede succeeded payments for the same run" do
      pending_sinpe_payment!
      succeeded = Payment.create!(
        user: user,
        nesting_run: run,
        status: "succeeded",
        paid_at: Time.current,
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_succeeded",
        onvo_mode: "test",
        gateway_status: "succeeded",
        created_at: 1.hour.ago
      )

      described_class.call(user: user, nesting_run: run)

      expect(succeeded.reload.superseded_at).to be_nil
    end

    it "[REQ-FIT-BILL-001] does not supersede pending payments for another nesting run" do
      other_pending = pending_sinpe_payment!(nesting_run: other_run)
      pending_sinpe_payment!

      described_class.call(user: user, nesting_run: run)

      expect(other_pending.reload.superseded_at).to be_nil
    end

    it "[REQ-FIT-BILL-001] skips payments already superseded" do
      payment = pending_sinpe_payment!(
        superseded_at: 1.minute.ago,
        checkout_lock_released_at: 1.minute.ago,
        checkout_lock_reason: "superseded"
      )
      superseded_at = payment.superseded_at

      described_class.call(user: user, nesting_run: run)

      expect(payment.reload.superseded_at).to eq(superseded_at)
    end
  end
end
