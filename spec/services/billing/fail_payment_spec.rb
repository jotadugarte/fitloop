# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::FailPayment, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }

  it "[REQ-FIT-BILL-001] marks pending payment failed with optional gateway fields" do
    payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_usd",
      currency: "usd",
      amount: 2,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_fail",
      onvo_mode: "test",
      gateway_status: "processing"
    )

    described_class.call(payment: payment, failure_code: "card_declined", failure_message: "Declined")

    payment.reload
    expect(payment).to be_failed
    expect(payment.gateway_status).to eq("failed")
    expect(payment.failure_code).to eq("card_declined")
    expect(payment.paid_at).to be_nil
  end

  describe "SINPE pre-retention staging purge [REQ-FIT-BILL-001]" do
    def pending_sinpe_payment!
      project = Project.create!(ephemeral: true, title: "Fail SINPE", status: :completed)
      run = project.nesting_runs.create!(status: "completed")
      project.nested_dxf.attach(
        io: StringIO.new("NESTED-FAIL"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_fail_sinpe_#{SecureRandom.hex(4)}",
        onvo_mode: "test",
        gateway_status: "processing"
      )
      { payment: payment, run: run }
    end

    it "[REQ-FIT-BILL-001] purges pre-retained staging blob when payment fails" do
      ctx = pending_sinpe_payment!
      grant = Billing::PreRetainNestedDxf.call(user: user, nesting_run: ctx[:run])

      expect(grant.retained_nested_dxf).to be_attached
      expect(grant.retention_active?).to be(false)

      described_class.call(payment: ctx[:payment], failure_code: "sinpe_failed", failure_message: "Transfer failed")

      ctx[:payment].reload
      grant.reload
      expect(ctx[:payment]).to be_failed
      expect(grant.retained_nested_dxf).not_to be_attached
      expect(grant.retained_until).to be_nil
    end

    it "[REQ-FIT-BILL-001] does not purge fulfilled grant with active retention" do
      ctx = pending_sinpe_payment!
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: ctx[:run],
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )
      grant.retained_nested_dxf.attach(
        io: StringIO.new("FULFILLED-BLOB"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      expect(grant.retention_active?).to be(true)

      described_class.call(payment: ctx[:payment], failure_code: "sinpe_failed")

      grant.reload
      expect(grant.retained_nested_dxf).to be_attached
      expect(grant.retention_active?).to be(true)
    end
  end
end
