# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::ConfirmSinpePayment, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:client) { instance_double(Billing::Onvo::Client) }
  let(:payment) do
    Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_sinpe_test",
      onvo_mode: "test",
      gateway_status: "requires_payment_method",
      total_amount: 1130
    )
  end

  it "[REQ-FIT-BILL-001] creates mobile_number method and confirms intent" do
    expect(client).to receive(:create_payment_method).with(
      hash_including(
        type: "mobile_number",
        mobileNumber: hash_including(identification: "1-2345-6789", number: "+50688887777")
      )
    ).and_return(id: "pm_mobile")

    expect(client).to receive(:confirm_payment_intent)
      .with("pi_sinpe_test", payment_method_id: "pm_mobile")
      .and_return(id: "pi_sinpe_test", status: "processing")

    result = described_class.call(
      payment: payment,
      identification: "1-2345-6789",
      mobile_number: "88887777",
      client: client
    )

    expect(result.fetch(:status)).to eq("processing")
    expect(result.fetch(:destination_number)).to include("506")
    expect(payment.reload.gateway_status).to eq("processing")
  end
end
