# frozen_string_literal: true

require "rails_helper"

RSpec.describe MisPagosHelper, "[REQ-FIT-BILL-002]", type: :helper do
  include BillingModelHelpers

  Row = Billing::MisPagos::SinglePurchaseRows::Row

  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Mis pagos row", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }

  def build_row(grant: nil, pending_payment: nil, display_payment: nil, sort_at: Time.current)
    Row.new(
      sort_at: sort_at,
      grant: grant,
      pending_payment: pending_payment,
      nesting_run: run,
      display_payment: display_payment
    )
  end

  before do
    allow(helper).to receive(:current_user).and_return(user)
  end

  describe "download row presentation" do
    it "labels expired grants that are no longer downloadable" do
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: :single_purchase,
        retained_until: 1.day.ago
      )
      row = build_row(grant: grant)

      expect(helper.mis_pagos_download_status_label(row)).to eq(
        I18n.t("billing.mis_pagos.download_status.expired")
      )
      expect(helper.mis_pagos_download_status_class(row)).to eq("status-badge--failed")
      expect(helper.mis_pagos_download_row_class(row)).to eq(
        "mis-pagos-download-row mis-pagos-download-row--expired"
      )
    end

    it "labels pending SINPE rows awaiting transfer confirmation" do
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_status: "processing"
      )
      row = build_row(pending_payment: payment)

      action = helper.mis_pagos_sinpe_primary_action(payment)

      expect(action[:label]).to eq(I18n.t("billing.checkout.onvo.sinpe_continue"))
      expect(action[:url]).to eq(helper.checkout_processing_path(payment))
      expect(action[:testid]).to eq("mis-pagos-sinpe-continue")
    end

    it "labels resumable SINPE rows that still need transfer details" do
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_status: "requires_payment_method"
      )

      action = helper.mis_pagos_sinpe_primary_action(payment)

      expect(action[:label]).to eq(I18n.t("billing.mis_pagos.sinpe_resume"))
      expect(action[:url]).to eq(
        helper.checkout_path(nesting_run_id: payment.nesting_run_id, payment_id: payment.id)
      )
      expect(action[:testid]).to eq("mis-pagos-sinpe-resume")
    end
  end

  describe "payment status presentation" do
    it "labels superseded payments distinctly from their raw status" do
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        superseded_at: Time.current
      )

      expect(helper.mis_pagos_payment_status_label(payment)).to eq(
        I18n.t("billing.mis_pagos.status.superseded")
      )
      expect(helper.mis_pagos_payment_status_badge_class(payment)).to eq("status-badge--failed")
    end

    it "maps failed statuses to the failed badge class" do
      expect(helper.mis_pagos_payment_status_badge_class_for_status("failed")).to eq(
        "status-badge--failed"
      )
    end
  end

  describe "row reference and facts" do
    it "falls back to legacy reference copy when purchase_reference is blank" do
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.5,
        total_amount: 2.5,
        purpose: "single_download",
        paid_at: Time.current
      )
      payment.update_column(:purchase_reference, nil)
      row = build_row(display_payment: payment)

      expect(helper.mis_pagos_row_reference(row)).to eq(
        I18n.t("billing.mis_pagos.row_reference_payment_legacy", id: payment.id)
      )
    end

    it "uses the attempt legacy reference for pending rows without purchase_reference" do
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download"
      )
      payment.update_column(:purchase_reference, nil)
      row = build_row(pending_payment: payment)

      expect(helper.mis_pagos_row_reference(row)).to eq(
        I18n.t("billing.mis_pagos.row_reference_attempt_legacy", id: payment.id)
      )
    end
  end
end
