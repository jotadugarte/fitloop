# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::CreatePaymentIntent, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:payment) do
    Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_crc",
      currency: "crc",
      amount: 1130,
      purpose: "single_download"
    )
  end

  let(:breakdown) do
    Billing::CheckoutBreakdown.for_single_download(
      billing_context: { currency: :crc, payment_method: :sinpe, iva_applicable: true },
      overage: false
    )
  end

  let(:client) { instance_double(Billing::Onvo::Client, mode: "test") }

  describe ".call [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] builds ONVO payload from CheckoutBreakdown and payment_id metadata" do
      expect(client).to receive(:create_payment_intent).with(
        amount: 113_000,
        currency: "CRC",
        description: "fiTLoop payment ##{payment.id}",
        metadata: { payment_id: payment.id.to_s }
      ).and_return(
        id: "pi_test_123",
        status: "requires_payment_method"
      )

      result = described_class.call(payment: payment, breakdown: breakdown, client: client)

      expect(result.fetch(:id)).to eq("pi_test_123")
      payment.reload
      expect(payment.gateway_provider).to eq("onvo")
      expect(payment.onvo_payment_intent_id).to eq("pi_test_123")
      expect(payment.onvo_mode).to eq("test")
      expect(payment.gateway_status).to eq("requires_payment_method")
      expect(payment).to be_pending
    end

    it "[REQ-FIT-BILL-001] rejects unpersisted payment" do
      draft = Payment.new(
        user: user,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download"
      )

      expect do
        described_class.call(payment: draft, breakdown: breakdown, client: client)
      end.to raise_error(ArgumentError, /persisted/)
    end
  end
end
