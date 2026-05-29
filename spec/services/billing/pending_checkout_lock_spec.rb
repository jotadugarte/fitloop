# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PendingCheckoutLock, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Lock spec", status: :completed) }
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
      onvo_payment_intent_id: "pi_lock_spec",
      onvo_mode: "test",
      gateway_status: "processing"
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
end
