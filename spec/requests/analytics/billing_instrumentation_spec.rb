# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Billing telemetry", "[REQ-FIT-ANALYTICS-001]", type: :request do
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }
  let(:project) { begin_workspace_session! }

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def attach_nested_output!(project)
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF CONTENT"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    run
  end

  describe "paywall_viewed event" do
    it "tracks paywall_viewed when download paywall is displayed" do
      sign_in_user! user
      attach_nested_output!(project)

      expect {
        get "/taller/descarga-pago"
      }.to have_enqueued_job(TrackEventJob).with("paywall_viewed", anything)
    end
  end

  describe "payment_succeeded and payment_failed events" do
    it "tracks payment_succeeded synchronously when payment is fulfilled" do
      run = attach_nested_output!(project)
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 5.0,
        purpose: "single_download"
      )

      expect {
        Billing::FulfillPayment.call(payment: payment)
      }.to change(UserEvent.where(event_type: "payment_succeeded"), :count).by(1)
    end

    it "tracks payment_failed synchronously when payment is failed" do
      run = attach_nested_output!(project)
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 5.0,
        purpose: "single_download"
      )

      expect {
        Billing::FailPayment.call(payment: payment, failure_code: "card_declined", failure_message: "Declined")
      }.to change(UserEvent.where(event_type: "payment_failed"), :count).by(1)
    end
  end

  describe "download_completed event" do
    context "for plan-based download" do
      before do
        create_active_subscription!(user: user)
        attach_nested_output!(project)
        sign_in_user! user
      end

      it "tracks download_completed synchronously on download" do
        expect {
          get nested_dxf_project_path(project)
        }.to change(UserEvent.where(event_type: "download_completed"), :count).by(1)
      end

      it "is idempotent on quick double requests" do
        subscription = Subscription.find_by(user: user)
        travel_to subscription.starts_at + 1.day do
          expect {
            get nested_dxf_project_path(project)
            get nested_dxf_project_path(project)
          }.to change(UserEvent.where(event_type: "download_completed"), :count).by(1)
        end
      end
    end

    context "for single purchase download" do
      let(:run) { attach_nested_output!(project) }
      let!(:grant) do
        DownloadGrant.create!(
          user: user,
          nesting_run: run,
          kind: "single_purchase",
          retained_until: 1.day.from_now
        ).tap do |g|
          g.retained_nested_dxf.attach(
            io: StringIO.new("NESTED DXF CONTENT"),
            filename: "nested.dxf",
            content_type: "application/dxf"
          )
        end
      end

      before do
        sign_in_user! user
      end

      it "tracks download_completed synchronously on download" do
        expect {
          get mis_pagos_download_path(grant)
        }.to change(UserEvent.where(event_type: "download_completed"), :count).by(1)
      end

      it "is idempotent on quick double requests" do
        travel_to Time.zone.parse("2026-06-06 12:00:00") do
          expected_key =
            "download_completed_grant_#{user.id}_#{run.id}_#{Time.current.to_i / 10}"

          expect {
            get mis_pagos_download_path(grant)
            get mis_pagos_download_path(grant)
          }.to change(UserEvent.where(idempotency_key: expected_key), :count).by(1)
        end
      end
    end
  end
end
