# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PendingCheckoutPolicy, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Policy spec", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }

  def pending_sinpe_payment!(created_at: Time.current, **attrs)
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
        onvo_payment_intent_id: "pi_policy_#{SecureRandom.hex(4)}",
        onvo_mode: "test",
        gateway_status: "processing",
        created_at: created_at
      }.merge(attrs)
    )
  end

  describe ".workshop_lock_minutes [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] reads onvo_pending_checkout.workshop_lock_minutes from billing.yml" do
      expect(described_class.workshop_lock_minutes).to eq(15)
    end
  end

  describe ".lock_expires_at [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] returns created_at plus configured workshop lock window" do
      created_at = Time.zone.parse("2026-05-28 10:00:00")
      payment = pending_sinpe_payment!(created_at: created_at)

      expect(described_class.lock_expires_at(payment)).to eq(created_at + 15.minutes)
    end
  end

  describe ".lock_active? [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] is true while current time is before lock_expires_at" do
      payment = pending_sinpe_payment!(created_at: 5.minutes.ago)

      expect(described_class.lock_active?(payment)).to be(true)
    end

    it "[REQ-FIT-BILL-001] is false after workshop_lock_minutes elapse" do
      payment = pending_sinpe_payment!(created_at: 16.minutes.ago)

      expect(described_class.lock_active?(payment)).to be(false)
    end
  end
end
