# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::MisPagos::SinglePurchaseRows, "[REQ-FIT-BILL-001] [REQ-FIT-BILL-002]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Rows spec", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }

  def pending_payment!
    Payment.create!(
      user: user,
      nesting_run: run,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      total_amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_rows_spec",
      onvo_mode: "test",
      gateway_status: "processing"
    )
  end

  it "[REQ-FIT-BILL-001] includes pending payment without grant as awaiting row" do
    payment = pending_payment!

    rows = described_class.build(user: user)

    expect(rows.length).to eq(1)
    expect(rows.first.pending_payment).to eq(payment)
    expect(rows.first.grant).to be_nil
  end

  it "[REQ-FIT-BILL-002] prefers grant row when payment succeeded and grant exists" do
    payment = pending_payment!
    payment.update!(status: :succeeded, paid_at: Time.current, gateway_status: "succeeded")
    grant = DownloadGrant.create!(
      user: user,
      nesting_run: run,
      kind: :single_purchase,
      retained_until: 1.day.from_now
    )

    rows = described_class.build(user: user)

    expect(rows.length).to eq(1)
    expect(rows.first.grant).to eq(grant)
    expect(rows.first.pending_payment).to be_nil
  end

  it "[REQ-FIT-BILL-001] excludes superseded pending payments from rows" do
    payment = pending_payment!
    payment.update!(superseded_at: Time.current, checkout_lock_released_at: Time.current, checkout_lock_reason: "superseded")

    rows = described_class.build(user: user)

    expect(rows).to be_empty
  end

  it "[REQ-FIT-BILL-001] includes expired-lock pending row without downloadable grant" do
    payment = pending_payment!
    payment.update!(created_at: 20.minutes.ago)

    rows = described_class.build(user: user)

    expect(rows.length).to eq(1)
    expect(rows.first.pending_payment).to eq(payment)
    expect(rows.first.pending_lock_expired?).to be(true)
    expect(rows.first.pending_lock_active?).to be(false)
    expect(rows.first.pending_cancelable?).to be(true)
    expect(rows.first.downloadable?).to be(false)
  end

  it "[REQ-FIT-BILL-001] marks abandoned pending row as not cancelable" do
    payment = pending_payment!
    payment.update!(
      created_at: 20.minutes.ago,
      checkout_abandoned_at: Time.current,
      checkout_lock_released_at: Time.current,
      checkout_lock_reason: "user_abandoned"
    )

    rows = described_class.build(user: user)

    expect(rows.length).to eq(1)
    expect(rows.first.pending_cancelable?).to be(false)
  end

  it "[REQ-FIT-BILL-001] shows grant row only when retention is active" do
    payment = pending_payment!
    payment.update!(status: :succeeded, paid_at: Time.current, gateway_status: "succeeded")
    grant = DownloadGrant.create!(
      user: user,
      nesting_run: run,
      kind: :single_purchase,
      retained_until: nil
    )

    rows = described_class.build(user: user)

    expect(rows).to be_empty
    grant.update!(retained_until: 1.day.from_now)
    rows = described_class.build(user: user)
    expect(rows.length).to eq(1)
    expect(rows.first.downloadable?).to be(true)
  end

  it "[REQ-FIT-BILL-001] shows pending row instead of older grant while a new payment is in flight" do
    DownloadGrant.create!(
      user: user,
      nesting_run: run,
      kind: :single_purchase,
      retained_until: 1.day.from_now,
      created_at: 2.days.ago,
      updated_at: 2.days.ago
    )
    payment = pending_payment!

    rows = described_class.build(user: user)

    expect(rows.length).to eq(1)
    expect(rows.first.pending_payment).to eq(payment)
    expect(rows.first.grant).to be_nil
  end
end
