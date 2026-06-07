# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::StartOnvoCheckout, "[REQ-FIT-BILL-001]" do
  include BillingModelHelpers

  let(:user) { create_billing_user! }
  let(:client) { instance_double(Billing::Onvo::Client) }
  let(:billing_context) do
    Billing::CheckoutContext.from_session(
      currency: :usd,
      payment_method: :card,
      iva_applicable: false,
      country_code: "US"
    )
  end

  def prepared_run!(attach_nested: true)
    project = Project.create!(ephemeral: true, title: "ONVO checkout", status: :completed)
    run = project.nesting_runs.create!(status: "completed")
    if attach_nested
      project.nested_dxf.attach(
        io: StringIO.new("NESTED"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
    end
    run
  end

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
    allow(Billing::Onvo::CreatePaymentIntent).to receive(:call).and_return({ id: "pi_start_onvo" })
  end

  it "rejects checkout when the ONVO gateway is disabled" do
    allow(Billing::Gateway).to receive(:onvo?).and_return(false)

    expect do
      described_class.call(
        user: user,
        payment_method: "card_usd",
        billing_context: billing_context,
        nesting_run: prepared_run!
      )
    end.to raise_error(ArgumentError, "ONVO gateway not enabled")
  end

  it "starts checkout from a cart snapshot" do
    run = prepared_run!
    cart = Cart.create!(
      kind: "single_download",
      nesting_run: run,
      user: user,
      currency_mode: "usd",
      overage: false,
      list_price_cents: 250,
      sinpe_price_cents: 200
    )

    result = described_class.call(
      user: user,
      payment_method: "card_usd",
      billing_context: billing_context,
      cart: cart,
      client: client
    )

    expect(result[:onvo_payment_intent_id]).to eq("pi_start_onvo")
    expect(result[:payment].amount).to eq(2.5)
    expect(result[:payment].purpose).to eq("single_download")
  end

  it "starts plan checkout with plan snapshot fields" do
    result = described_class.call(
      user: user,
      payment_method: "card_usd",
      billing_context: billing_context,
      tier_months: 2,
      client: client
    )

    payment = result[:payment]
    expect(payment.purpose).to eq("plan_subscription")
    expect(payment.product_description).to eq("plan_2_months")
    expect(payment.amount).to eq(Billing::Pricing.plan_2_months_card_usd)
  end

  it "applies overage pricing when the active plan quota is exhausted" do
    run = prepared_run!
    subscription = create_active_subscription!(user: user)
    PlanMonthlyUsage.create!(
      subscription: subscription,
      period_year: Time.current.year,
      period_month: Time.current.month,
      downloads_used: 50,
      quota_limit: 50
    )

    result = described_class.call(
      user: user,
      payment_method: "card_usd",
      billing_context: billing_context,
      nesting_run: run,
      client: client
    )

    expect(result[:payment].amount).to eq(Billing::Pricing.single_download_overage_official_usd)
  end

  it "abandons prior incomplete card attempts before starting a new card checkout" do
    run = prepared_run!
    prior = Payment.create!(
      user: user,
      nesting_run: run,
      status: "pending",
      payment_method: "card_usd",
      currency: "usd",
      amount: 2.5,
      total_amount: 2.5,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_prior_card",
      onvo_mode: "test",
      gateway_status: "requires_action"
    )

    described_class.call(
      user: user,
      payment_method: "card_usd",
      billing_context: billing_context,
      nesting_run: run,
      client: client
    )

    prior.reload
    expect(prior.checkout_abandoned_at).to be_present
    expect(prior.checkout_lock_reason).to eq(Billing::CheckoutLockReason::USER_CANCELED_3DS)
  end

  it "supersedes prior SINPE attempts and pre-retains nested DXF for a new SINPE checkout" do
    run = prepared_run!
    prior = Payment.create!(
      user: user,
      nesting_run: run,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      total_amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_prior_sinpe",
      onvo_mode: "test",
      gateway_status: "processing"
    )
    sinpe_context = Billing::CheckoutContext.from_session(
      currency: :crc,
      payment_method: :sinpe,
      iva_applicable: true,
      country_code: "CR"
    )

    result = described_class.call(
      user: user,
      payment_method: "sinpe_crc",
      billing_context: sinpe_context,
      nesting_run: run,
      client: client
    )

    prior.reload
    expect(prior.superseded_at).to be_present
    expect(result[:payment].payment_method).to eq("sinpe_crc")
    grant = DownloadGrant.find_by!(user_id: user.id, nesting_run_id: run.id)
    expect(grant.retained_nested_dxf).to be_attached
    expect(grant.retained_until).to be_nil
  end
end
