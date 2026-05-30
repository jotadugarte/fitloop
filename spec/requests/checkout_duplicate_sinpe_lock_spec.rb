# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Duplicate SINPE checkout guard", "[REQ-FIT-BILL-001]", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
    allow(Billing::Gateway).to receive(:onvo?).and_return(true)
    allow(Billing::Onvo::CreatePaymentIntent).to receive(:call).and_return({ id: "pi_new_checkout" })
  end

  def setup_checkout_project!
    get start_project_path
    follow_redirect!
    project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
    project.update!(title: "Dup guard", status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    run = project.nesting_runs.create!(status: "completed")
    { project: project, run: run }
  end

  describe "POST /checkout/pagar [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] blocks duplicate SINPE checkout while workshop lock is active" do
      ctx = setup_checkout_project!
      Payment.create!(
        user: user,
        nesting_run: ctx[:run],
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_existing_lock",
        onvo_mode: "test",
        gateway_status: "processing",
        created_at: 5.minutes.ago
      )

      post checkout_pay_path,
           params: { payment_method: "sinpe_crc", nesting_run_id: ctx[:run].id },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:conflict)
      body = response.parsed_body
      expect(body["error"]).to eq(I18n.t("billing.checkout.pending_lock.duplicate_checkout_blocked"))
      expect(body["redirect_url"]).to eq(mis_pagos_path)
    end

    it "[REQ-FIT-BILL-001] allows new SINPE checkout after workshop lock expires" do
      ctx = setup_checkout_project!
      Payment.create!(
        user: user,
        nesting_run: ctx[:run],
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_expired_lock",
        onvo_mode: "test",
        gateway_status: "processing",
        created_at: 20.minutes.ago
      )

      post checkout_pay_path,
           params: { payment_method: "sinpe_crc", nesting_run_id: ctx[:run].id },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
    end
  end
end
