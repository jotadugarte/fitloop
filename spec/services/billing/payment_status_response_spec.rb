# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PaymentStatusResponse, "[REQ-FIT-BILL-001]", type: :service do
  include Rails.application.routes.url_helpers

  let(:user) { create_billing_user! }

  it "[REQ-FIT-BILL-001] returns pending status without redirect" do
    payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_crc",
      currency: "crc",
      amount: 100,
      purpose: "single_download"
    )

    payload = described_class.for(payment: payment, routes: self)

    expect(payload.fetch(:status)).to eq("pending")
    expect(payload.fetch(:redirect_url)).to be_nil
    expect(payload.fetch(:checkout_lock_active)).to be(false)
    expect(payload.fetch(:checkout_lock_expired)).to be(false)
    expect(payload.fetch(:release_pending_url)).to be_nil
    expect(payload.fetch(:retry_checkout_url)).to be_nil
  end

  it "[REQ-FIT-BILL-001] includes lock and action URLs for active SINPE pending checkout" do
    run = create_nesting_run!
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
      onvo_payment_intent_id: "pi_status_lock",
      onvo_mode: "test",
      gateway_status: "processing",
      created_at: 5.minutes.ago
    )

    payload = described_class.for(payment: payment, routes: self)

    expect(payload.fetch(:checkout_lock_active)).to be(true)
    expect(payload.fetch(:checkout_lock_expired)).to be(false)
    expect(payload.fetch(:release_pending_url)).to eq(checkout_release_pending_lock_path(payment))
    expect(payload.fetch(:retry_checkout_url)).to be_nil
  end

  it "[REQ-FIT-BILL-001] exposes retry URL when SINPE lock expired but payment still pending" do
    run = create_nesting_run!
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
      onvo_payment_intent_id: "pi_status_expired",
      onvo_mode: "test",
      gateway_status: "processing",
      created_at: 20.minutes.ago
    )

    payload = described_class.for(payment: payment, routes: self)

    expect(payload.fetch(:checkout_lock_active)).to be(false)
    expect(payload.fetch(:checkout_lock_expired)).to be(true)
    expect(payload.fetch(:release_pending_url)).to be_nil
    expect(payload.fetch(:retry_checkout_url)).to eq(checkout_path(nesting_run_id: run.id))
  end

  it "returns mis pagos success for succeeded plan payments" do
    payment = Payment.create!(
      user: user,
      status: "succeeded",
      payment_method: "card_usd",
      currency: "usd",
      amount: 7,
      total_amount: 7,
      purpose: "plan_subscription",
      gateway_status: "succeeded",
      paid_at: Time.current
    )

    payload = described_class.for(payment: payment, routes: self)

    expect(payload.fetch(:redirect_url)).to eq(mis_pagos_path(payment_succeeded: 1))
  end

  it "returns checkout failed for declined non-card pending payments" do
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
      onvo_payment_intent_id: "pi_declined_sinpe",
      onvo_mode: "test",
      gateway_status: "requires_payment_method"
    )

    payload = described_class.for(payment: payment, routes: self)

    expect(payload.fetch(:checkout_return_url)).to eq(checkout_payment_failed_path(payment))
  end

  it "returns checkout canceled for incomplete declined card attempts" do
    payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_usd",
      currency: "usd",
      amount: 2.5,
      total_amount: 2.5,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_declined_card",
      onvo_mode: "test",
      gateway_status: "requires_payment_method"
    )

    payload = described_class.for(payment: payment, routes: self)

    expect(payload.fetch(:checkout_return_url)).to eq(checkout_payment_canceled_path(payment))
  end

  it "returns checkout failed for terminal failed payments" do
    payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "failed",
      payment_method: "card_usd",
      currency: "usd",
      amount: 2.5,
      total_amount: 2.5,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_failed_card",
      onvo_mode: "test",
      gateway_status: "failed"
    )

    payload = described_class.for(payment: payment, routes: self)

    expect(payload.fetch(:checkout_failed_url)).to eq(checkout_payment_failed_path(payment))
  end
end
