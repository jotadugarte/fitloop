# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ONVO checkout pay", "[REQ-FIT-BILL-001]", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }
  let(:client) { instance_double(Billing::Onvo::Client, mode: "test") }
  let!(:checkout_context) { prepare_single_download! }
  let(:run) { checkout_context[:run] }

  around do |example|
    keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET ONVO_MODE]
    previous = keys.index_with { |key| ENV[key] }
    ENV["BILLING_GATEWAY"] = "onvo"
    ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
    ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
    ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
    ENV["ONVO_MODE"] = "test"
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before do
    sign_in_user! user
    allow(Billing::Onvo::Client).to receive(:from_env).and_return(client)
    allow(client).to receive(:create_payment_intent).and_return(
      id: "pi_spec_checkout_intent",
      status: "requires_payment_method"
    )
  end

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def prepare_single_download!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF ONVO PAY"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    { project: project, run: run }
  end

  describe "POST /checkout/pagar [REQ-FIT-BILL-001]" do
    it "creates pending Payment, pre-retains nested DXF, and returns ONVO intent id" do
      expect do
        post checkout_pay_path,
             params: { nesting_run_id: run.id, payment_method: "sinpe_crc" },
             headers: { "CF-IPCountry" => "CR" }
      end.to change(Payment, :count).by(1).and change(DownloadGrant, :count).by(1)

      expect(response).to have_http_status(:ok)

      body = JSON.parse(response.body)
      expect(body.fetch("onvo_payment_intent_id")).to eq("pi_spec_checkout_intent")
      expect(body.fetch("payment_id")).to eq(Payment.last.id)
      expect(body.fetch("onvo_publishable_key")).to eq("onvo_test_publishable_spec")

      payment = Payment.last
      expect(payment).to be_pending
      expect(payment.gateway_provider).to eq("onvo")
      expect(payment.onvo_payment_intent_id).to eq("pi_spec_checkout_intent")
      expect(payment.paid_at).to be_nil

      grant = DownloadGrant.find_by(user_id: user.id, nesting_run_id: run.id)
      expect(grant).to be_present
      expect(grant.retained_until).to be_nil
      expect(grant.retention_active?).to be(false)
      expect(grant.retained_nested_dxf).to be_attached
    end

    it "[REQ-FIT-BILL-001] hides demo badge on checkout when BILLING_GATEWAY=onvo" do
      get checkout_path(nesting_run_id: run.id), headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-testid="checkout-demo"')
    end
  end
end
