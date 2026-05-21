# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Simulated plan checkout", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  describe "GET /planes without session [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] redirects to sign-in with a translated unauthenticated message" do
      I18n.with_locale(:es) do
        get "/planes"

        expect(response).to redirect_to(new_user_session_path)
        follow_redirect!

        expect(response.body).to include(I18n.t("devise.failure.user.unauthenticated"))
        expect(response.body).not_to include("translation missing")
      end
    end
  end

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "POST /planes/simular [REQ-FIT-BILL-002]" do
    let(:user) { create_billing_user! }
    let(:project) { begin_workspace_session! }

    before { sign_in_user! user }

    it "[REQ-FIT-BILL-002] creates subscription with ends_at from payment instant for first purchase (D29)" do
      paid_at = Time.zone.parse("2026-05-15 10:00:00")

      travel_to(paid_at) do
        expect do
          post planes_simulate_path,
               params: {
                 tier_months: 1,
                 payment_method: "card_usd",
                 outcome: "success",
                 project_id: project.id
               }
        end.to change(Subscription, :count).by(1)
          .and change(Payment, :count).by(1)

        subscription = Subscription.last
        expect(subscription.user_id).to eq(user.id)
        expect(subscription.tier_months).to eq(1)
        expect(subscription.starts_at).to be_within(2.seconds).of(paid_at)
        expect(subscription.ends_at).to eq(
          Billing::PlanPeriod.ends_at_for(
            starts_at: paid_at,
            tier_months: 1,
            time_zone: user.time_zone
          )
        )

        payment = Payment.last
        expect(payment).to be_succeeded
        expect(payment.purpose).to eq("plan_subscription")
        expect(payment.amount).to eq(Billing::Pricing.plan_1_month_card_usd)
      end
    end

    it "[REQ-FIT-BILL-002] extends ends_at from current plan end when buying again (D28)" do
      existing_ends = Time.zone.parse("2026-06-20 23:59:59")
      create_active_subscription!(user: user, tier_months: 1, ends_at: existing_ends)
      paid_at = Time.zone.parse("2026-05-18 12:00:00")

      travel_to(paid_at) do
        expect do
          post planes_simulate_path,
               params: {
                 tier_months: 2,
                 payment_method: "sinpe_crc",
                 outcome: "success",
                 project_id: project.id
               }
        end.to change(Subscription, :count).by(0)
          .and change(Payment, :count).by(1)

        subscription = user.subscriptions.reload.sole
        expect(subscription.ends_at).to eq(
          Billing::PlanPeriod.ends_at_for(
            starts_at: existing_ends,
            tier_months: 2,
            time_zone: user.time_zone
          )
        )

        payment = Payment.last
        expect(payment.payment_method).to eq("sinpe_crc")
        expect(payment.currency).to eq("crc")
        expect(payment.amount).to eq(Billing::Pricing.plan_2_months_sinpe_crc)
      end
    end

    it "[REQ-FIT-BILL-002] blocks suspended users from plan purchase (D46)" do
      user.update!(suspended_at: Time.current)

      expect do
        post planes_simulate_path,
             params: {
               tier_months: 1,
               payment_method: "card_usd",
               outcome: "success",
               project_id: project.id
             }
      end.not_to change(Subscription, :count)

      expect(response).to redirect_to("/mi-cuenta")
      expect(flash[:alert]).to be_present
    end
  end
end
