# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout release pending lock", "[REQ-FIT-BILL-001]", type: :request do
  let(:user) { create_billing_user! }

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def pending_sinpe_payment!
    project = Project.create!(ephemeral: true, title: "Release lock", status: :completed)
    run = project.nesting_runs.create!(status: "completed")
    payment = Payment.create!(
      user: user,
      nesting_run: run,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      total_amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_release_#{SecureRandom.hex(4)}",
      onvo_mode: "test",
      gateway_status: "processing",
      created_at: 5.minutes.ago
    )
    { payment: payment, run: run }
  end

  describe "POST /checkout/pagos/:id/liberar [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] releases workshop lock and keeps payment pending" do
      ctx = pending_sinpe_payment!

      post checkout_release_pending_lock_path(ctx[:payment])

      expect(response).to redirect_to(mis_pagos_path)
      ctx[:payment].reload
      expect(ctx[:payment]).to be_pending
      expect(ctx[:payment].checkout_abandoned_at).to be_present
      expect(ctx[:payment].checkout_lock_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] forbids releasing another user payment" do
      ctx = pending_sinpe_payment!
      other = create_billing_user!(email: "other-release@example.com")
      delete destroy_user_session_path
      post user_session_path, params: { user: { email: other.email, password: "securepassword12" } }

      post checkout_release_pending_lock_path(ctx[:payment])

      expect(response).to have_http_status(:not_found)
    end
  end
end
