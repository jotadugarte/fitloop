# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ONVO SINPE checkout confirm", "[REQ-FIT-BILL-001]", type: :request do
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

  it "[REQ-FIT-BILL-001] confirms SINPE after pay and returns transfer instructions" do
    payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      total_amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_sinpe_req",
      onvo_mode: "test",
      gateway_status: "requires_payment_method"
    )

    expect(client).to receive(:create_payment_method).and_return(id: "pm_1")
    expect(client).to receive(:confirm_payment_intent).and_return(id: "pi_sinpe_req", status: "processing")

    post checkout_confirm_sinpe_path(payment),
         params: { sinpe_identification: "1-2345-6789", sinpe_mobile_number: "88887777" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.fetch("status")).to eq("processing")
    expect(body.fetch("destination_number")).to be_present
    expect(body.fetch("destination_holder_name")).to eq(Billing::Onvo::SinpeDestination.holder_name)
    expect(payment.reload.gateway_status).to eq("processing")
  end
end
