# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::HandleWebhookEvent, "[REQ-FIT-BILL-001]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Webhook handler", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }

  def pending_payment!(intent_id: "pi_handler_spec", **attrs)
    Payment.create!(
      {
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: intent_id,
        onvo_mode: "test",
        gateway_status: "processing"
      }.merge(attrs)
    )
  end

  it "[REQ-FIT-BILL-001] fulfills payment on payment-intent.succeeded" do
    payment = pending_payment!
    project.nested_dxf.attach(
      io: StringIO.new("NESTED"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )

    result = described_class.call(
      payload: {
        type: "payment-intent.succeeded",
        data: { id: payment.onvo_payment_intent_id, status: "succeeded" }
      }
    )

    expect(result).to eq(:fulfilled)
    expect(payment.reload).to be_succeeded
  end

  it "[REQ-FIT-BILL-001] is idempotent when payment already succeeded" do
    payment = pending_payment!(status: :succeeded, paid_at: Time.current, gateway_status: "succeeded")

    result = described_class.call(
      payload: {
        type: "payment-intent.succeeded",
        data: { id: payment.onvo_payment_intent_id, status: "succeeded" }
      }
    )

    expect(result).to eq(:already_fulfilled)
  end

  it "[REQ-FIT-BILL-001] fails payment on payment-intent.failed" do
    payment = pending_payment!

    result = described_class.call(
      payload: {
        type: "payment-intent.failed",
        data: { id: payment.onvo_payment_intent_id, status: "failed" }
      }
    )

    expect(result).to eq(:failed)
    expect(payment.reload).to be_failed
  end

  it "[REQ-FIT-BILL-001] abandons incomplete card checkout instead of failing on payment-intent.failed" do
    payment = pending_payment!(
      intent_id: "pi_card_abandon",
      payment_method: "card_crc",
      gateway_status: "requires_action"
    )

    result = described_class.call(
      payload: {
        type: "payment-intent.failed",
        data: { id: payment.onvo_payment_intent_id, status: "failed" }
      }
    )

    expect(result).to eq(:abandoned)
    expect(payment.reload).to be_pending
    expect(payment.checkout_abandoned_at).to be_present
    expect(payment.checkout_lock_reason).to eq(Billing::CheckoutLockReason::USER_CANCELED_3DS)
  end

  it "[REQ-FIT-BILL-001] raises PaymentNotFound for unknown intent id" do
    expect do
      described_class.call(
        payload: {
          type: "payment-intent.succeeded",
          data: { id: "pi_missing", status: "succeeded" }
        }
      )
    end.to raise_error(described_class::PaymentNotFound)
  end

  it "[REQ-FIT-BILL-001] ignores unknown event types" do
    payment = pending_payment!(intent_id: "pi_ignored")

    result = described_class.call(
      payload: {
        type: "payment-intent.processing",
        data: { id: payment.onvo_payment_intent_id, status: "processing" }
      }
    )

    expect(result).to eq(:ignored)
    expect(payment.reload).to be_pending
  end
end
