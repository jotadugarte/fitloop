# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::SimulateSingleDownload, "[REQ-FIT-BILL-001]" do
  include BillingModelHelpers

  let(:user) { create_billing_user! }

  def prepared_run!(attach_nested: true)
    project = Project.create!(ephemeral: true, title: "Simulate single", status: :completed)
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

  it "rejects suspended users" do
    user.update!(suspended_at: Time.current)

    expect do
      described_class.call(
        user: user,
        nesting_run: prepared_run!,
        payment_method: "card_usd",
        outcome: "success",
        iva_applicable: false
      )
    end.to raise_error(ArgumentError, "user suspended")
  end

  it "rejects checkout when plan quota still covers the download" do
    create_active_subscription!(user: user)
    run = prepared_run!

    expect do
      described_class.call(
        user: user,
        nesting_run: run,
        payment_method: "card_usd",
        outcome: "success",
        iva_applicable: false
      )
    end.to raise_error(ArgumentError, /active plan monthly quota/)
  end

  it "rejects checkout when nested_dxf is missing" do
    run = prepared_run!(attach_nested: false)

    expect do
      described_class.call(
        user: user,
        nesting_run: run,
        payment_method: "card_usd",
        outcome: "success",
        iva_applicable: false
      )
    end.to raise_error(ArgumentError, "nested_dxf missing")
  end

  it "records a failed payment without creating a grant" do
    run = prepared_run!

    expect do
      described_class.call(
        user: user,
        nesting_run: run,
        payment_method: "card_usd",
        outcome: "failure",
        iva_applicable: false
      )
    end.to change(Payment, :count).by(1)
      .and change(DownloadGrant, :count).by(0)

    expect(Payment.last).to be_failed
  end

  it "uses cart price snapshots when currency_mode matches" do
    run = prepared_run!
    Cart.create!(
      kind: "single_download",
      nesting_run: run,
      user: user,
      currency_mode: "usd",
      overage: false,
      list_price_cents: 275,
      sinpe_price_cents: 225
    )

    result = described_class.call(
      user: user,
      nesting_run: run,
      payment_method: "card_usd",
      outcome: "success",
      iva_applicable: false
    )

    expect(result[:payment].amount).to eq(2.75)
    expect(result[:grant]).to be_present
  end

  it "ignores cart rows when currency_mode does not match the payment method" do
    run = prepared_run!
    Cart.create!(
      kind: "single_download",
      nesting_run: run,
      user: user,
      currency_mode: "crc",
      overage: false,
      list_price_cents: 1200,
      sinpe_price_cents: 1000
    )

    result = described_class.call(
      user: user,
      nesting_run: run,
      payment_method: "card_usd",
      outcome: "success",
      iva_applicable: false
    )

    expect(result[:payment].amount).to eq(Billing::Pricing.single_download_official_usd)
  end

  it "reuses an active retained grant without creating a duplicate" do
    run = prepared_run!
    described_class.call(
      user: user,
      nesting_run: run,
      payment_method: "card_usd",
      outcome: "success",
      iva_applicable: false
    )
    grant = DownloadGrant.find_by!(user: user, nesting_run: run)
    payment = Payment.succeeded.order(:created_at).last

    expect do
      result = described_class.call(
        user: user,
        nesting_run: run,
        payment_method: "sinpe_crc",
        outcome: "success",
        iva_applicable: true
      )
      expect(result[:grant].id).to eq(grant.id)
      expect(result[:payment].id).to eq(payment.id)
    end.not_to change(DownloadGrant, :count)
  end

  it "applies plan overage pricing when monthly quota is exhausted" do
    subscription = create_active_subscription!(user: user)
    allow(Billing::PlanDownloadAvailability).to receive(:single_download_checkout_allowed?).and_return(true)
    allow(Billing::QuotaCounter).to receive(:for).with(subscription).and_return(
      instance_double(Billing::QuotaCounter, exhausted?: true)
    )
    run = prepared_run!

    result = described_class.call(
      user: user,
      nesting_run: run,
      payment_method: "sinpe_crc",
      outcome: "success",
      iva_applicable: true
    )

    expect(result[:payment].amount).to eq(Billing::Pricing.single_download_overage_sinpe_crc)
  end
end
