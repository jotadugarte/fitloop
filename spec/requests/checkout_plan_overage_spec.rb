# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Single download with plan overage pricing", type: :request do
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

  describe "POST /checkout/simular [REQ-FIT-BILL-002]" do
    let(:user) { create_billing_user! }
    let!(:checkout_context) { prepare_single_download! }
    let(:run) { checkout_context[:run] }

    before do
      subscription = create_active_subscription!(user: user)
      PlanMonthlyUsage.create!(
        subscription: subscription,
        period_year: Time.current.year,
        period_month: Time.current.month,
        downloads_used: 50,
        quota_limit: 50
      )
      sign_in_user! user
    end

    it "[REQ-FIT-BILL-002] charges 50% overage price when plan monthly quota is exhausted (D34)" do
      expect do
        post checkout_simulate_path,
             params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
      end.to change(Payment, :count).by(1)

      payment = Payment.last
      expect(payment).to be_succeeded
      expect(payment.amount).to eq(Billing::Pricing.single_download_overage_usd)
      expect(payment.purpose).to eq("single_download")
    end

    it "[REQ-FIT-BILL-002] charges 50% overage in CRC via SINPE when quota exhausted (D34)" do
      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "sinpe_crc", outcome: "success" }

      expect(Payment.last.amount).to eq(Billing::Pricing.single_download_overage_sinpe_crc)
    end
  end
end
