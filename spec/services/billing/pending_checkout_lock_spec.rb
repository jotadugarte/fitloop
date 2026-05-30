# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PendingCheckoutLock, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Lock spec", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }

  def pending_payment!(**attrs)
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
        onvo_payment_intent_id: "pi_lock_spec_#{SecureRandom.hex(4)}",
        onvo_mode: "test",
        gateway_status: "processing"
      }.merge(attrs)
    )
  end

  it "[REQ-FIT-BILL-001] is active when user has pending single-download payment for project" do
    pending_payment!

    lock = described_class.for(project: project, user: user)

    expect(lock).to be_active
    expect(lock.payment_id).to eq(Payment.last.id)
  end

  it "[REQ-FIT-BILL-001] is inactive when payment succeeded" do
    payment = pending_payment!
    payment.update!(status: :succeeded, paid_at: Time.current, gateway_status: "succeeded")

    expect(described_class.for(project: project, user: user)).to be_nil
  end

  it "[REQ-FIT-BILL-001] is inactive for another user" do
    pending_payment!
    other = create_billing_user!(email: "other-lock@example.com")

    expect(described_class.for(project: project, user: other)).to be_nil
  end

  it "[REQ-FIT-BILL-001] for_user returns newest pending single-download payment" do
    payment = pending_payment!

    lock = described_class.for_user(user: user)

    expect(lock).to be_active
    expect(lock.payment_id).to eq(payment.id)
  end

  it "[REQ-FIT-BILL-001] stays active when an older grant exists for the same nesting run" do
    DownloadGrant.create!(
      user: user,
      nesting_run: run,
      kind: :single_purchase,
      retained_until: 1.day.from_now,
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )
    payment = pending_payment!

    lock = described_class.for(project: project, user: user)

    expect(lock).to be_active
    expect(lock.payment_id).to eq(payment.id)
  end

  it "[REQ-FIT-BILL-001] is inactive when grant was refreshed after the pending payment started" do
    payment = pending_payment!(created_at: 2.hours.ago)
    DownloadGrant.create!(
      user: user,
      nesting_run: run,
      kind: :single_purchase,
      retained_until: 1.day.from_now,
      created_at: 3.hours.ago,
      updated_at: Time.current
    )

    expect(described_class.for(project: project, user: user)).to be_nil
    expect(described_class.for_user(user: user)).to be_nil
  end

  describe "SINPE checkout_lock_active? window [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] is active for sinpe_crc pending within workshop_lock_minutes" do
      payment = pending_payment!(created_at: 5.minutes.ago)

      expect(described_class.new(payment: payment).active?).to be(true)
      expect(described_class.for(project: project, user: user)).to be_active
    end

    it "[REQ-FIT-BILL-001] is inactive after workshop_lock_minutes elapse" do
      payment = pending_payment!(created_at: 16.minutes.ago)

      expect(described_class.new(payment: payment).active?).to be(false)
      expect(described_class.for(project: project, user: user)).to be_nil
    end

    it "[REQ-FIT-BILL-001] lazily persists checkout_lock_released_at after timeout on first active? read" do
      payment = pending_payment!(created_at: 16.minutes.ago)

      described_class.new(payment: payment).active?

      payment.reload
      expect(payment.checkout_lock_released_at).to be_present
      expect(payment.checkout_lock_reason).to eq("timeout")
    end

    it "[REQ-FIT-BILL-001] is inactive after manual abandon" do
      payment = pending_payment!(
        created_at: 5.minutes.ago,
        checkout_abandoned_at: 1.minute.ago,
        checkout_lock_released_at: 1.minute.ago
      )

      expect(described_class.new(payment: payment).active?).to be(false)
      expect(described_class.for_user(user: user)).to be_nil
    end

    it "[REQ-FIT-BILL-001] is inactive for card pending within workshop lock window" do
      payment = pending_payment!(payment_method: "card_crc", created_at: 5.minutes.ago)

      expect(described_class.new(payment: payment).active?).to be(false)
      expect(described_class.for(project: project, user: user)).to be_nil
    end

    it "[REQ-FIT-BILL-001] is inactive when superseded_at is set" do
      payment = pending_payment!(
        created_at: 5.minutes.ago,
        superseded_at: 1.minute.ago,
        checkout_lock_released_at: 1.minute.ago
      )

      expect(described_class.new(payment: payment).active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] does not re-lock after late fulfillment grants downloadable access" do
      payment = pending_payment!(created_at: 16.minutes.ago)
      DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )

      expect(described_class.new(payment: payment).active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] stays active with pre-retained grant without retained_until" do
      payment = pending_payment!(created_at: 5.minutes.ago)
      DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: nil
      )

      expect(described_class.new(payment: payment).active?).to be(true)
    end
  end

  it "[REQ-FIT-BILL-001] is inactive when a newer succeeded payment exists for the same run" do
    pending_payment!(
      created_at: 2.hours.ago,
      onvo_payment_intent_id: "pi_old_pending"
    )
    Payment.create!(
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
      onvo_payment_intent_id: "pi_new_succeeded",
      onvo_mode: "test",
      gateway_status: "succeeded",
      created_at: 1.hour.ago
    )

    expect(described_class.for(project: project, user: user)).to be_nil
    expect(described_class.for_user(user: user)).to be_nil
  end
end
