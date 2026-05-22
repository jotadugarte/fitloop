# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Simulated single-download checkout", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def prepare_single_download!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF CONTENT"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    { project: project, run: run }
  end

  describe "GET /checkout [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] shows demo badge and card/SINPE simulate actions (D37)" do
      user = create_billing_user!
      run = prepare_single_download![:run]
      sign_in_user! user

      get checkout_path(nesting_run_id: run.id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('class="paywall-layout checkout-page"')
      expect(response.body).to include('data-testid="checkout-demo"')
      expect(response.body).to include('data-testid="checkout-pay-card-usd"')
      expect(response.body).to include('data-testid="checkout-pay-sinpe-crc"')
      expect(response.body).to include('data-testid="checkout-simulate-success"')
      expect(response.body).to include('data-testid="checkout-simulate-failure"')
    end
  end

  describe "POST /checkout/simular [REQ-FIT-BILL-001]" do
    let(:user) { create_billing_user! }
    let!(:checkout_context) { prepare_single_download! }
    let(:run) { checkout_context[:run] }

    before { sign_in_user! user }

    it "[REQ-FIT-BILL-001] records succeeded card USD payment and single_purchase grant (D37)" do
      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
      end.to change(Payment, :count).by(1)
        .and change(DownloadGrant, :count).by(1)

      grant = DownloadGrant.last
      expect(response).to redirect_to(mis_pagos_path(auto_download: grant.id))

      payment = Payment.last
      expect(payment).to be_succeeded
      expect(payment.user_id).to eq(user.id)
      expect(payment.nesting_run_id).to eq(run.id)
      expect(payment.payment_method).to eq("card_usd")
      expect(payment.currency).to eq("usd")
      expect(payment.amount).to eq(Billing::Pricing.single_download_usd)
      expect(payment.purpose).to eq("single_download")
      expect(payment.paid_at).to be_present

      grant = DownloadGrant.last
      expect(grant.user_id).to eq(user.id)
      expect(grant.nesting_run_id).to eq(run.id)
      expect(grant.kind).to eq("single_purchase")
    end

    it "[REQ-FIT-BILL-001] records succeeded SINPE CRC payment and grant (D37)" do
      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "sinpe_crc", outcome: "success" }
      end.to change(Payment, :count).by(1)
        .and change(DownloadGrant, :count).by(1)

      payment = Payment.last
      expect(payment).to be_succeeded
      expect(payment.payment_method).to eq("sinpe_crc")
      expect(payment.currency).to eq("crc")
      expect(payment.amount).to eq(Billing::Pricing.single_download_sinpe_crc)
      expect(payment.purpose).to eq("single_download")

      expect(DownloadGrant.last.kind).to eq("single_purchase")
      expect(response).to redirect_to(mis_pagos_path(auto_download: DownloadGrant.last.id))
    end

    it "[REQ-FIT-BILL-001] reuses existing grant on repeat success without error (D37)" do
      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
      grant = DownloadGrant.last

      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "sinpe_crc", outcome: "success" }
      end.not_to change(DownloadGrant, :count)

      expect(response).to redirect_to(mis_pagos_path(auto_download: grant.id))
    end

    it "[REQ-FIT-BILL-001] records failed payment without grant when simulate fails (D37)" do
      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "failure" }
      end.to change(Payment, :count).by(1)
        .and change(DownloadGrant, :count).by(0)

      payment = Payment.last
      expect(payment).to be_failed
      expect(payment.user_id).to eq(user.id)
      expect(payment.nesting_run_id).to eq(run.id)
      expect(payment.paid_at).to be_nil
    end
  end
end
