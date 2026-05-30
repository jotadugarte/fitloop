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
        mobileNumber: hash_including(identification: "123456789", number: "+50688888888")
      )
    ).and_return(id: "pm_mobile")

    expect(client).to receive(:confirm_payment_intent)
      .with("pi_sinpe_test", payment_method_id: "pm_mobile")
      .and_return(id: "pi_sinpe_test", status: "processing")

    result = described_class.call(
      payment: payment,
      identification: "123456789",
      mobile_number: "88888888",
      client: client
    )

    expect(result.fetch(:status)).to eq("processing")
    expect(result.fetch(:destination_number)).to include("506")
    expect(result.fetch(:destination_holder_name)).to eq(Billing::Onvo::SinpeDestination.holder_name)
    expect(result.fetch(:transfer_identification)).to eq("123456789")
    expect(result.fetch(:transfer_mobile_number)).to eq("88888888")
    payment.reload
    expect(payment.gateway_status).to eq("processing")
    expect(payment.sinpe_transfer_identification).to eq("123456789")
    expect(payment.sinpe_transfer_mobile_number).to eq("88888888")
  end

  it "[REQ-FIT-BILL-001] returns instructions without ONVO when same transferor and status still requires_payment_method" do
    payment.update!(
      gateway_status: "requires_payment_method",
      sinpe_transfer_identification: "123456789",
      sinpe_transfer_mobile_number: "88888888"
    )

    expect(client).not_to receive(:create_payment_method)

    result = described_class.call(
      payment: payment.reload,
      identification: "123456789",
      mobile_number: "88888888",
      client: client
    )

    expect(result.fetch(:transfer_identification)).to eq("123456789")
  end

  it "[REQ-FIT-BILL-001] returns instructions without calling ONVO when transfer already confirmed" do
    payment.update!(
      gateway_status: "processing",
      sinpe_transfer_identification: "123456789",
      sinpe_transfer_mobile_number: "88888888"
    )

    expect(client).not_to receive(:create_payment_method)
    expect(client).not_to receive(:confirm_payment_intent)

    result = described_class.call(
      payment: payment.reload,
      identification: "123456789",
      mobile_number: "88888888",
      client: client
    )

    expect(result.fetch(:status)).to eq("processing")
    expect(result.fetch(:transfer_identification)).to eq("123456789")
  end

  it "[REQ-FIT-BILL-001] updates stored transferor fields when awaiting transfer with new data" do
    payment.update!(
      gateway_status: "processing",
      sinpe_transfer_identification: "123456789",
      sinpe_transfer_mobile_number: "88888888"
    )

    expect(client).not_to receive(:create_payment_method)

    described_class.call(
      payment: payment.reload,
      identification: "987654321",
      mobile_number: "88888888",
      client: client
    )

    payment.reload
    expect(payment.sinpe_transfer_identification).to eq("987654321")
  end

  it "[REQ-FIT-BILL-001] does not re-call ONVO when reverting transferor data after a prior edit" do
    payment.update!(
      gateway_status: "requires_payment_method",
      sinpe_transfer_identification: "134124141451",
      sinpe_transfer_mobile_number: "88884444"
    )

    expect(client).not_to receive(:create_payment_method)

    result = described_class.call(
      payment: payment.reload,
      identification: "134124141451",
      mobile_number: "88888888",
      client: client
    )

    payment.reload
    expect(payment.sinpe_transfer_mobile_number).to eq("88888888")
    expect(result.fetch(:transfer_mobile_number)).to eq("88888888")
  end
end
