# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ONVO 3DS return", "[REQ-FIT-BILL-001]", type: :request do
  let(:user) { create_billing_user! }
  let(:client) { instance_double(Billing::Onvo::Client) }

  around do |example|
    keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_WEBHOOK_SECRET ONVO_MODE]
    previous = keys.index_with { |key| ENV[key] }
    ENV["BILLING_GATEWAY"] = "onvo"
    ENV["ONVO_SECRET_KEY"] = "onvo_test_secret"
    ENV["ONVO_WEBHOOK_SECRET"] = "whsec_test"
    ENV["ONVO_MODE"] = "test"
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before do
    sign_in_user! user
    allow(Billing::Onvo::Client).to receive(:from_env).and_return(client)
  end

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /checkout/retorno [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] reconciles intent and redirects to processing after 3DS" do
      payment = Payment.create!(
        user: user,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_3ds_return",
        onvo_mode: "test",
        gateway_status: "requires_action"
      )

      expect(client).to receive(:get_payment_intent).with("pi_3ds_return").and_return(
        id: "pi_3ds_return",
        status: "processing"
      )

      get checkout_return_path, params: { payment_intent_id: "pi_3ds_return" }

      expect(response).to redirect_to(checkout_processing_path(payment))
      expect(payment.reload.gateway_status).to eq("processing")
    end

    it "[REQ-FIT-BILL-001] returns to checkout when 3DS was canceled" do
      run = create_nesting_run!
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_3ds_canceled",
        onvo_mode: "test",
        gateway_status: "requires_action"
      )

      expect(client).to receive(:get_payment_intent).with("pi_3ds_canceled").and_return(
        id: "pi_3ds_canceled",
        status: "requires_payment_method"
      )

      get checkout_return_path, params: { payment_intent_id: "pi_3ds_canceled" }

      expect(response).to redirect_to(checkout_payment_canceled_path(payment))
      expect(payment.reload.gateway_status).to eq("requires_payment_method")

      follow_redirect!

      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id, payment_method: "card_crc"))
      expect(flash[:alert]).to eq(I18n.t("billing.checkout.onvo.payment_canceled"))
      expect(payment.reload).to be_pending
      expect(payment).not_to be_failed
      expect(payment.checkout_abandoned_at).to be_present
      expect(payment.checkout_lock_reason).to eq("user_canceled_3ds")
    end

    it "[REQ-FIT-BILL-001] returns not found for unknown payment intent" do
      get checkout_return_path, params: { payment_intent_id: "pi_missing" }

      expect(response).to have_http_status(:not_found)
    end
  end
end
