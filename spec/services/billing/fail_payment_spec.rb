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
end
