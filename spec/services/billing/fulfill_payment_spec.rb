# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::FulfillPayment, "[REQ-FIT-BILL-001] [REQ-FIT-BILL-002]", type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }

  describe "single_download [REQ-FIT-BILL-001] [REQ-FIT-BILL-003]" do
    def pending_single_payment!
      project = Project.create!(ephemeral: true, title: "Fulfill nest", status: :completed)
      run = project.nesting_runs.create!(status: "completed")
      project.nested_dxf.attach(
        io: StringIO.new("NESTED"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        purchaser_name: user.name,
        purchaser_email: user.email,
        total_amount: 1130
      )
      { payment: payment, run: run, project: project }
    end

    it "[REQ-FIT-BILL-001] marks pending payment succeeded and creates retained DownloadGrant" do
      ctx = pending_single_payment!

      expect do
        described_class.call(payment: ctx[:payment])
      end.to change(DownloadGrant, :count).by(1)

      ctx[:payment].reload
      expect(ctx[:payment]).to be_succeeded
      expect(ctx[:payment].paid_at).to be_present

      grant = DownloadGrant.find_by(user_id: user.id, nesting_run_id: ctx[:run].id)
      expect(grant.retained_nested_dxf).to be_attached
    end

    it "[REQ-FIT-BILL-001] is idempotent when payment already succeeded" do
      ctx = pending_single_payment!
      described_class.call(payment: ctx[:payment])

      expect do
        described_class.call(payment: ctx[:payment])
      end.not_to change(DownloadGrant, :count)
    end

    def pending_sinpe_payment!
      project = Project.create!(ephemeral: true, title: "Fulfill SINPE", status: :completed)
      run = project.nesting_runs.create!(status: "completed")
      project.nested_dxf.attach(
        io: StringIO.new("NESTED-SINPE"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_fulfill_#{SecureRandom.hex(4)}",
        onvo_mode: "test",
        gateway_status: "processing",
        total_amount: 1130
      )
      { payment: payment, run: run, project: project }
    end

    describe "SINPE pre-retention and late webhook [REQ-FIT-BILL-001]" do
      it "[REQ-FIT-BILL-001] fulfills pending payment after checkout was abandoned and activates retention" do
        ctx = pending_sinpe_payment!
        ctx[:payment].update!(
          checkout_abandoned_at: 2.minutes.ago,
          checkout_lock_released_at: 2.minutes.ago,
          checkout_lock_reason: "user_abandoned"
        )

        described_class.call(payment: ctx[:payment])

        ctx[:payment].reload
        expect(ctx[:payment]).to be_succeeded
        grant = DownloadGrant.find_by!(user_id: user.id, nesting_run_id: ctx[:run].id)
        expect(grant.retention_active?).to be(true)
        expect(grant.retained_nested_dxf).to be_attached
      end

      it "[REQ-FIT-BILL-001] sets retained_until on pre-retained staging grant" do
        ctx = pending_sinpe_payment!
        grant = Billing::PreRetainNestedDxf.call(user: user, nesting_run: ctx[:run])
        expect(grant.retained_until).to be_nil

        paid_at = Time.zone.parse("2026-06-15 14:00:00")
        travel_to(paid_at) do
          described_class.call(payment: ctx[:payment])

          grant.reload
          expect(grant.retention_active?).to be(true)
          expect(grant.retained_until).to eq(paid_at + Billing::RetainNestedDxf::RETENTION_HOURS.hours)
        end
      end

      it "[REQ-FIT-BILL-001] keeps pre-retained blob when project nested_dxf changes before fulfill" do
        ctx = pending_sinpe_payment!
        Billing::PreRetainNestedDxf.call(user: user, nesting_run: ctx[:run])

        ctx[:project].nested_dxf.purge
        ctx[:project].nested_dxf.attach(
          io: StringIO.new("RE-NESTED-DXF"),
          filename: "nested.dxf",
          content_type: "application/dxf"
        )

        described_class.call(payment: ctx[:payment])

        grant = DownloadGrant.find_by!(user_id: user.id, nesting_run_id: ctx[:run].id)
        expect(grant.retained_nested_dxf.download).to include("NESTED-SINPE")
        expect(grant.retained_nested_dxf.download).not_to include("RE-NESTED-DXF")
      end
    end

    it "[REQ-FIT-BILL-001] refreshes retention when grant already active for the nesting run" do
      ctx = pending_single_payment!
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: ctx[:run],
        kind: :single_purchase,
        retained_until: 1.hour.from_now,
        created_at: 2.days.ago,
        updated_at: 2.days.ago
      )

      described_class.call(payment: ctx[:payment])

      grant.reload
      expect(grant.updated_at).to be > 2.days.ago
      expect(grant.retained_until).to be > 1.hour.from_now
      expect(grant.retained_nested_dxf).to be_attached
    end
  end

  describe "plan_subscription [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] creates subscription and marks payment succeeded" do
      paid_at = Time.zone.parse("2026-05-18 12:00:00")
      payment = nil

      travel_to(paid_at) do
        payment = Payment.create!(
          user: user,
          status: "pending",
          payment_method: "card_usd",
          currency: "usd",
          amount: Billing::Pricing.plan_1_month_card_usd,
          purpose: "plan_subscription",
          product_description: "plan_1_months"
        )

        expect do
          described_class.call(payment: payment)
        end.to change(Subscription, :count).by(1)
      end

      payment.reload
      subscription = Subscription.last
      expect(payment).to be_succeeded
      expect(payment.subscription_id).to eq(subscription.id)
      expect(subscription.tier_months).to eq(1)
      expect(subscription.starts_at).to be_within(2.seconds).of(paid_at)
    end

    it "[REQ-FIT-BILL-002] extends ends_at when user already has an active plan (D28)" do
      existing_ends = Time.zone.parse("2026-06-20 23:59:59")
      create_active_subscription!(
        user: user,
        tier_months: 1,
        starts_at: Time.zone.parse("2026-05-01 00:00:00"),
        ends_at: existing_ends
      )
      paid_at = Time.zone.parse("2026-05-18 12:00:00")

      travel_to(paid_at) do
        payment = Payment.create!(
          user: user,
          status: "pending",
          payment_method: "sinpe_crc",
          currency: "crc",
          amount: 10_000,
          purpose: "plan_subscription",
          product_description: "plan_2_months"
        )

        expect do
          described_class.call(payment: payment)
        end.not_to change(Subscription, :count)

        payment.reload
        expect(payment.subscription.ends_at).to be_within(1.second).of(
          Billing::PlanPeriod.ends_at_for(
            starts_at: existing_ends,
            tier_months: 2,
            time_zone: user.time_zone
          )
        )
      end
    end
  end
end
