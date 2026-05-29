# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ONVO checkout payment status", "[REQ-FIT-BILL-001]", type: :request do
  let(:user) { create_billing_user! }

  around do |example|
    previous = ENV["BILLING_GATEWAY"]
    ENV["BILLING_GATEWAY"] = "onvo"
    example.run
  ensure
    previous.nil? ? ENV.delete("BILLING_GATEWAY") : ENV["BILLING_GATEWAY"] = previous
  end

  before do
    sign_in_user! user
  end

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /checkout/pagos/:payment_id/estado [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] returns payment status from the database without granting access" do
      payment = Payment.create!(
        user: user,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_status_test",
        onvo_mode: "test",
        gateway_status: "processing"
      )

      get checkout_payment_status_path(payment)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.fetch("status")).to eq("pending")
      expect(body.fetch("gateway_status")).to eq("processing")
      expect(body.fetch("redirect_url")).to be_nil
      expect(body.fetch("checkout_return_url")).to be_nil
      expect(DownloadGrant.count).to eq(0)
    end

    it "[REQ-FIT-BILL-001] returns checkout_return_url when gateway abandoned 3DS" do
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
        onvo_payment_intent_id: "pi_abandoned",
        onvo_mode: "test",
        gateway_status: "requires_payment_method"
      )

      get checkout_payment_status_path(payment)

      body = JSON.parse(response.body)
      expect(body.fetch("checkout_return_url")).to eq(
        checkout_path(nesting_run_id: run.id, payment_canceled: 1)
      )
    end

    it "[REQ-FIT-BILL-001] returns redirect_url when payment succeeded and grant exists" do
      project = Project.create!(ephemeral: true, title: "Status nest", status: :completed)
      run = project.nesting_runs.create!(status: "completed")
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "succeeded",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        paid_at: Time.current,
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_status_succeeded",
        onvo_mode: "test",
        gateway_status: "succeeded"
      )
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )

      get checkout_payment_status_path(payment)

      body = JSON.parse(response.body)
      expect(body.fetch("status")).to eq("succeeded")
      expect(body.fetch("redirect_url")).to eq(
        mis_pagos_path(auto_download: grant.id, payment_succeeded: 1)
      )
    end

    it "[REQ-FIT-BILL-001] forbids accessing another user payment" do
      other = create_billing_user!(email: "other-status@example.com")
      payment = Payment.create!(
        user: other,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download"
      )

      get checkout_payment_status_path(payment)

      expect(response).to have_http_status(:not_found)
    end
  end
end
