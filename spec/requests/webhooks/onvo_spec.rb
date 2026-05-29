# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ONVO webhooks", "[REQ-FIT-BILL-001]", type: :request do
  let(:webhook_secret) { "whsec_test_onvo" }

  before do
    @previous_webhook_secret = ENV["ONVO_WEBHOOK_SECRET"]
    ENV["ONVO_WEBHOOK_SECRET"] = webhook_secret
  end

  after do
    if @previous_webhook_secret.nil?
      ENV.delete("ONVO_WEBHOOK_SECRET")
    else
      ENV["ONVO_WEBHOOK_SECRET"] = @previous_webhook_secret
    end
  end

  def post_onvo_webhook!(payload, secret: webhook_secret)
    post "/webhooks/onvo",
         params: payload.to_json,
         headers: {
           "CONTENT_TYPE" => "application/json",
           "X-Webhook-Secret" => secret
         }
  end

  def prepare_pending_onvo_payment!(intent_id: "pi_webhook_test")
    user = create_billing_user!(email: "onvo-webhook@example.com")
    project = Project.create!(ephemeral: true, title: "Webhook nest", status: :completed)
    run = project.nesting_runs.create!(status: "completed")
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF FOR WEBHOOK"),
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
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: intent_id,
      onvo_mode: "test",
      gateway_status: "processing"
    )
    { payment: payment, run: run }
  end

  describe "POST /webhooks/onvo [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] marks Payment succeeded and creates DownloadGrant on payment-intent.succeeded" do
      ctx = prepare_pending_onvo_payment!
      payload = {
        type: "payment-intent.succeeded",
        data: { id: ctx[:payment].onvo_payment_intent_id, status: "succeeded" }
      }

      expect do
        post_onvo_webhook!(payload)
      end.to change(DownloadGrant, :count).by(1)

      expect(response).to have_http_status(:ok)
      ctx[:payment].reload
      expect(ctx[:payment]).to be_succeeded
      expect(ctx[:payment].gateway_status).to eq("succeeded")
      expect(ctx[:payment].paid_at).to be_present

      grant = DownloadGrant.find_by(user_id: ctx[:payment].user_id, nesting_run_id: ctx[:run].id)
      expect(grant).to be_single_purchase
      expect(grant.retained_nested_dxf).to be_attached
    end

    it "[REQ-FIT-BILL-001] returns 401 when X-Webhook-Secret is missing or invalid" do
      ctx = prepare_pending_onvo_payment!(intent_id: "pi_unauthorized")
      payload = { type: "payment-intent.succeeded", data: { id: ctx[:payment].onvo_payment_intent_id } }

      post_onvo_webhook!(payload, secret: "wrong-secret")

      expect(response).to have_http_status(:unauthorized)
      expect(ctx[:payment].reload).to be_pending
      expect(DownloadGrant.count).to eq(0)
    end

    it "[REQ-FIT-BILL-001] marks Payment failed and preserves checkout snapshot on payment-intent.failed" do
      ctx = prepare_pending_onvo_payment!(intent_id: "pi_failed_webhook")
      payment = ctx[:payment]
      payment.update!(
        purchaser_name: "Webhook Buyer",
        purchaser_email: "buyer@example.com",
        product_description: "single_download",
        list_price: 10.0,
        discount_amount: 1.0,
        subtotal: 9.0,
        tax_amount: 1.17,
        total_amount: 10.17
      )
      snapshot_before = payment.attributes.slice(
        "purchaser_name", "purchaser_email", "product_description",
        "list_price", "discount_amount", "subtotal", "tax_amount", "total_amount",
        "amount", "currency", "payment_method", "purpose"
      )

      payload = {
        type: "payment-intent.failed",
        data: {
          id: payment.onvo_payment_intent_id,
          status: "failed",
          last_payment_error: { code: "card_declined", message: "Your card was declined." }
        }
      }

      expect do
        post_onvo_webhook!(payload)
      end.not_to change(DownloadGrant, :count)

      expect(response).to have_http_status(:ok)
      payment.reload
      expect(payment).to be_failed
      expect(payment.gateway_status).to eq("failed")
      expect(payment.paid_at).to be_nil
      expect(payment.attributes.slice(*snapshot_before.keys)).to eq(snapshot_before)
    end

    it "[REQ-FIT-BILL-001] is idempotent when the same succeeded webhook is delivered twice" do
      ctx = prepare_pending_onvo_payment!(intent_id: "pi_idempotent")
      payload = { type: "payment-intent.succeeded", data: { id: "pi_idempotent", status: "succeeded" } }

      post_onvo_webhook!(payload)
      expect(response).to have_http_status(:ok)

      expect do
        post_onvo_webhook!(payload)
      end.not_to change(DownloadGrant, :count)

      expect(response).to have_http_status(:ok)
      expect(DownloadGrant.where(user_id: ctx[:payment].user_id, nesting_run_id: ctx[:run].id).count).to eq(1)
    end
  end
end
