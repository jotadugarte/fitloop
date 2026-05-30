# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ONVO card checkout confirm", "[REQ-FIT-BILL-001]", type: :request do
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

  it "[REQ-FIT-BILL-001] confirms card after pay and returns processing status" do
    payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_crc",
      currency: "crc",
      amount: 1356,
      total_amount: 1356,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_card_req",
      onvo_mode: "test",
      gateway_status: "requires_payment_method"
    )

    expect(client).to receive(:create_payment_method).with(hash_including(type: "card")).and_return(id: "pm_card")
    expect(client).to receive(:confirm_payment_intent).with(
      "pi_card_req",
      payment_method_id: "pm_card",
      return_url: a_string_including("/checkout/retorno")
    ).and_return(id: "pi_card_req", status: "processing")

    post checkout_confirm_card_path(payment),
         params: {
           card_holder_name: "María Rodríguez",
           card_number: "4242424242424242",
           card_exp: "12/28",
           card_cvv: "123"
         }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.fetch("status")).to eq("processing")
    expect(body.fetch("redirect_url")).to be_nil
    expect(payment.reload.gateway_status).to eq("processing")
  end
end
