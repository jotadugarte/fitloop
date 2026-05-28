# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Simulated single-download checkout", "[REQ-FIT-BILL-001]", type: :request do
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
    it "[REQ-FIT-BILL-001] shows demo badge, payment method selector, and a single process-payment CTA (D37)" do
      user = create_billing_user!
      run = prepare_single_download![:run]
      sign_in_user! user

      get checkout_path(nesting_run_id: run.id), headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('class="paywall-layout checkout-page"')
      expect(response.body).to include('data-testid="checkout-demo"')
      expect(response.body).to include('data-testid="checkout-method-selector"')
      expect(response.body).to include('value="sinpe_crc"')
      expect(response.body).to include('value="card_crc"')
      expect(response.body).not_to include('value="card_usd"')
      expect(response.body).to include('data-testid="checkout-process-payment"')
    end
  end

  describe "POST /checkout/simular [REQ-FIT-BILL-001]" do
    let(:user) { create_billing_user! }
    let!(:checkout_context) { prepare_single_download! }
    let(:run) { checkout_context[:run] }

    before { sign_in_user! user }

    it "[REQ-FIT-BILL-001] records succeeded card USD payment without IVA for international clients (D37)" do
      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" },
             headers: { "CF-IPCountry" => "US" }
      end.to change(Payment, :count).by(1)
        .and change(DownloadGrant, :count).by(1)

      grant = DownloadGrant.last
      expect(response).to redirect_to(mis_pagos_path(auto_download: grant.id))

      payment = Payment.last
      expect(payment).to be_succeeded
      expect(payment.payment_method).to eq("card_usd")
      expect(payment.currency).to eq("usd")
      expect(payment.amount).to eq(Billing::Pricing.single_download_official_usd)
      expect(payment.tax_amount).to eq(0)
      expect(payment.total_amount).to eq(Billing::Pricing.single_download_official_usd)
      expect(payment.purpose).to eq("single_download")
    end

    it "[REQ-FIT-BILL-001] records succeeded SINPE CRC payment with 13% IVA (D37)" do
      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "sinpe_crc", outcome: "success" },
             headers: { "CF-IPCountry" => "CR" }
      end.to change(Payment, :count).by(1)
        .and change(DownloadGrant, :count).by(1)

      payment = Payment.last
      expect(payment).to be_succeeded
      expect(payment.payment_method).to eq("sinpe_crc")
      expect(payment.currency).to eq("crc")
      expect(payment.amount).to eq(Billing::Pricing.single_download_sinpe_crc)
      expect(payment.subtotal).to eq(1000)
      expect(payment.tax_amount).to eq(130)
      expect(payment.total_amount).to eq(1130)
      expect(DownloadGrant.last.kind).to eq("single_purchase")
    end

    it "[REQ-FIT-BILL-001] reuses existing grant on repeat success without error (D37)" do
      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" },
           headers: { "CF-IPCountry" => "US" }
      grant = DownloadGrant.last

      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "sinpe_crc", outcome: "success" },
             headers: { "CF-IPCountry" => "CR" }
      end.not_to change(DownloadGrant, :count)

      expect(response).to redirect_to(mis_pagos_path(auto_download: grant.id))
    end

    it "[REQ-FIT-BILL-001] records failed payment without grant when simulate fails (D37)" do
      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "failure" },
             headers: { "CF-IPCountry" => "US" }
      end.to change(Payment, :count).by(1)
        .and change(DownloadGrant, :count).by(0)

      payment = Payment.last
      expect(payment).to be_failed
      expect(payment.user_id).to eq(user.id)
      expect(payment.nesting_run_id).to eq(run.id)
      expect(payment.paid_at).to be_nil

      expect(payment.purchaser_name).to be_present
      expect(payment.purchaser_email).to be_present
      expect(payment.product_description).to be_present
      expect(payment.list_price).to be > 0
      expect(payment.total_amount).to be > 0
    end
  end
end
