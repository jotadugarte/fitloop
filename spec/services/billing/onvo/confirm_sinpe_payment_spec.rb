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

  it "[REQ-FIT-BILL-001] skips already-confirmed checks for non-SINPE payments" do
    card_payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_crc",
      currency: "crc",
      amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_card_branch",
      onvo_mode: "test",
      gateway_status: "requires_payment_method",
      total_amount: 1130
    )

    expect(client).to receive(:create_payment_method).and_return(id: "pm_card")
    expect(client).to receive(:confirm_payment_intent).and_return(id: "pi_card_branch", status: "processing")

    described_class.call(
      payment: card_payment,
      identification: "123456789",
      mobile_number: "88888888",
      client: client
    )
  end

  it "[REQ-FIT-BILL-001] requires a payment object" do
    expect do
      described_class.call(payment: nil, identification: "123456789", mobile_number: "88888888")
    end.to raise_error(ArgumentError, /payment required/)
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

  it "[REQ-FIT-BILL-001] rejects missing payment, transferor fields, or ONVO intent" do
    expect do
      described_class.call(payment: nil, identification: "1", mobile_number: "88888888", client: client)
    end.to raise_error(ArgumentError, /payment required/)

    expect do
      described_class.call(payment: payment, identification: "", mobile_number: "88888888", client: client)
    end.to raise_error(ArgumentError, /identification required/)

    expect do
      described_class.call(payment: payment, identification: "1", mobile_number: "", client: client)
    end.to raise_error(ArgumentError, /mobile_number required/)

    blank_intent = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_sinpe_branch",
      onvo_mode: "test",
      gateway_status: "requires_payment_method",
      total_amount: 1130
    )
    blank_intent.update_column(:onvo_payment_intent_id, nil)
    expect do
      described_class.call(payment: blank_intent, identification: "1", mobile_number: "88888888", client: client)
    end.to raise_error(ArgumentError, /ONVO intent required/)
  end

  it "[REQ-FIT-BILL-001] normalizes eight-digit Costa Rica numbers" do
    expect(client).to receive(:create_payment_method).with(
      hash_including(mobileNumber: hash_including(number: "+50688888888"))
    ).and_return(id: "pm_mobile")
    expect(client).to receive(:confirm_payment_intent).and_return(id: "pi_sinpe_test", status: "processing")

    described_class.call(
      payment: payment,
      identification: "123456789",
      mobile_number: "88888888",
      client: client
    )
  end

  it "[REQ-FIT-BILL-001] confirms non-eight-digit mobile numbers without adding 506" do
    expect(client).to receive(:create_payment_method).with(
      hash_including(mobileNumber: hash_including(number: "+888888889"))
    ).and_return(id: "pm_mobile")
    expect(client).to receive(:confirm_payment_intent).and_return(id: "pi_sinpe_test", status: "processing")

    described_class.call(
      payment: payment,
      identification: "123456789",
      mobile_number: "888888889",
      client: client
    )
  end

  it "[REQ-FIT-BILL-001] preserves already-prefixed international numbers" do
    expect(client).to receive(:create_payment_method).with(
      hash_including(mobileNumber: hash_including(number: "+15551234567"))
    ).and_return(id: "pm_mobile")
    expect(client).to receive(:confirm_payment_intent).and_return(id: "pi_sinpe_test", status: "processing")

    described_class.call(
      payment: payment,
      identification: "123456789",
      mobile_number: "+15551234567",
      client: client
    )
  end
end
