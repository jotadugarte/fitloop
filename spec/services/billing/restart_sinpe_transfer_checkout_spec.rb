# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RestartSinpeTransferCheckout, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:payment) do
    Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      total_amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_restart",
      onvo_mode: "test",
      gateway_status: "processing",
      sinpe_transfer_identification: "123456789",
      sinpe_transfer_mobile_number: "88888888"
    )
  end

  it "[REQ-FIT-BILL-001] supersedes payment after SINPE transfer step started" do
    described_class.call(payment: payment, user: user)

    payment.reload
    expect(payment.superseded_at).to be_present
    expect(payment.checkout_lock_reason).to eq("restarted_sinpe_transfer")
  end

  it "[REQ-FIT-BILL-001] rejects restart before transfer step" do
    payment.update!(sinpe_transfer_identification: nil, gateway_status: "requires_payment_method")

    expect do
      described_class.call(payment: payment.reload, user: user)
    end.to raise_error(ArgumentError, "not_restartable")
  end
end
