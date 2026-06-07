# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::ConfirmCardPayment, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:client) { instance_double(Billing::Onvo::Client) }
  let(:payment) do
    Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_crc",
      currency: "crc",
      amount: 1356,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_card_test",
      onvo_mode: "test",
      gateway_status: "requires_payment_method",
      total_amount: 1356
    )
  end

  it "[REQ-FIT-BILL-001] creates card method and confirms intent with returnUrl" do
    expect(client).to receive(:create_payment_method).with(
      hash_including(
        type: "card",
        card: hash_including(
          number: "4242424242424242",
          expMonth: 12,
          expYear: 2028,
          cvv: "123",
          holderName: "María Rodríguez"
        )
      )
    ).and_return(id: "pm_card")

    expect(client).to receive(:confirm_payment_intent).with(
      "pi_card_test",
      payment_method_id: "pm_card",
      return_url: "https://fitloop.test/checkout/retorno"
    ).and_return(id: "pi_card_test", status: "processing")

    result = described_class.call(
      payment: payment,
      holder_name: "María Rodríguez",
      card_number: "4242 4242 4242 4242",
      exp_month: 12,
      exp_year: 2028,
      cvv: "123",
      return_url: "https://fitloop.test/checkout/retorno",
      client: client
    )

    expect(result.fetch(:status)).to eq("processing")
    expect(result.fetch(:redirect_url)).to be_nil
    expect(payment.reload.gateway_status).to eq("processing")
  end

  it "[REQ-FIT-BILL-001] returns redirect_url when 3DS is required" do
    expect(client).to receive(:create_payment_method).and_return(id: "pm_card")
    expect(client).to receive(:confirm_payment_intent).and_return(
      id: "pi_card_test",
      status: "requires_action",
      nextAction: {
        type: "redirect_to_url",
        redirectToUrl: { url: "https://checkout.onvopay.com/authorize/test" }
      }
    )

    result = described_class.call(
      payment: payment,
      holder_name: "María Rodríguez",
      card_number: "4242424242424242",
      exp_month: 12,
      exp_year: 2028,
      cvv: "123",
      return_url: "https://fitloop.test/checkout/retorno",
      client: client
    )

    expect(result.fetch(:redirect_url)).to eq("https://checkout.onvopay.com/authorize/test")
    expect(payment.reload.gateway_status).to eq("requires_action")
  end

  it "[REQ-FIT-BILL-001] rejects missing payment, intent, or non-card methods" do
    expect do
      described_class.call(
        payment: nil,
        holder_name: "Test",
        card_number: "4242424242424242",
        exp_month: 12,
        exp_year: 2028,
        cvv: "123",
        return_url: "https://fitloop.test/return",
        client: client
      )
    end.to raise_error(ArgumentError, /payment required/)

    intentless = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_crc",
      currency: "crc",
      amount: 1356,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_card_test",
      onvo_mode: "test",
      gateway_status: "requires_payment_method",
      total_amount: 1356
    )
    intentless.update_column(:onvo_payment_intent_id, nil)
    expect do
      described_class.call(
        payment: intentless,
        holder_name: "Test",
        card_number: "4242424242424242",
        exp_month: 12,
        exp_year: 2028,
        cvv: "123",
        return_url: "https://fitloop.test/return",
        client: client
      )
    end.to raise_error(ArgumentError, /ONVO intent required/)

    sinpe_payment = Payment.create!(
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
    expect do
      described_class.call(
        payment: sinpe_payment,
        holder_name: "Test",
        card_number: "4242424242424242",
        exp_month: 12,
        exp_year: 2028,
        cvv: "123",
        return_url: "https://fitloop.test/return",
        client: client
      )
    end.to raise_error(ArgumentError, /card payment required/)
  end

  it "[REQ-FIT-BILL-001] omits return_url when blank and resolves snake_case 3DS URLs" do
    usd_payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_usd",
      currency: "usd",
      amount: 2.5,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_card_usd",
      onvo_mode: "test",
      gateway_status: "requires_payment_method",
      total_amount: 2.5
    )
    expect(client).to receive(:create_payment_method).and_return(id: "pm_card")
    expect(client).to receive(:confirm_payment_intent).with(
      "pi_card_usd",
      payment_method_id: "pm_card",
      return_url: nil
    ).and_return(
      id: "pi_card_usd",
      status: "requires_action",
      next_action: { redirect_to_url: { url: "https://checkout.onvopay.com/snake" } }
    )

    result = described_class.call(
      payment: usd_payment,
      holder_name: "Test User",
      card_number: "4242424242424242",
      exp_month: 12,
      exp_year: 2028,
      cvv: "123",
      return_url: "",
      client: client
    )

    expect(result.fetch(:redirect_url)).to eq("https://checkout.onvopay.com/snake")
  end
end
