# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::AnalyticsController", "[REQ-FIT-ANALYTICS-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  let(:admin_user) { create_billing_user!(email: "admin-analytics-view@example.com") }

  before do
    admin_user.update!(admin: true)
    sign_in_user! admin_user

    # Let's seed some funnel events
    # 10 workspace_started
    10.times do |i|
      UserEvent.create!(
        event_type: "workspace_started",
        occurred_at: Time.current - i.hours,
        priority: "low",
        anonymous_session_key: "anon-#{i}"
      )
    end

    # 5 paywall_viewed
    5.times do |i|
      UserEvent.create!(
        event_type: "paywall_viewed",
        occurred_at: Time.current - i.hours,
        priority: "low",
        anonymous_session_key: "anon-#{i}"
      )
    end
  end

  context "when conversion is healthy" do
    before do
      # 3 payment_succeeded (3/5 = 60%, assuming min threshold is 20%)
      3.times do |i|
        UserEvent.create!(
          event_type: "payment_succeeded",
          occurred_at: Time.current - i.hours,
          priority: "critical",
          anonymous_session_key: "anon-#{i}"
        )
      end
    end

    it "displays KPI cards and funnel counts without alert classes" do
      get "/admin/analytics"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("workspace_started")
      expect(response.body).to include("paywall_viewed")
      expect(response.body).to include("payment_succeeded")
      expect(response.body).not_to include("metric--alert")
    end
  end

  context "when conversion is below threshold" do
    before do
      # 0 payment_succeeded (0/5 = 0% < min threshold)
      # No succeeded events seeded here
    end

    it "renders the conversion card with the metric--alert class" do
      get "/admin/analytics"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("metric--alert")
    end
  end

  describe "Monetization KPIs" do
    before do
      # Seed some payments
      # Succeeded single download payment
      Payment.create!(
        user: admin_user,
        amount: 5.0,
        currency: "usd",
        payment_method: "card_usd",
        purpose: "single_download",
        status: "succeeded",
        paid_at: Time.current
      )

      # Succeeded plan subscription payment (1 month tier)
      sub = Subscription.create!(
        user: admin_user,
        tier_months: 1,
        starts_at: Time.current,
        ends_at: Time.current + 1.month
      )
      Payment.create!(
        user: admin_user,
        amount: 20.0,
        currency: "usd",
        payment_method: "card_usd",
        purpose: "plan_subscription",
        status: "succeeded",
        paid_at: Time.current,
        subscription: sub
      )

      # Seed plan monthly usage that is exhausted (downloads_used: 50, quota_limit: 50)
      PlanMonthlyUsage.create!(
        subscription: sub,
        period_year: Time.current.year,
        period_month: Time.current.month,
        quota_limit: 50,
        downloads_used: 50
      )
    end

    it "displays single vs plan payments, plans by tier, and exhausted quota counts" do
      get "/admin/analytics"

      expect(response.body).to include(I18n.t("admin.analytics.monetization.single_payments"))
      expect(response.body).to include(I18n.t("admin.analytics.monetization.plan_payments"))
      expect(response.body).to include(I18n.t("admin.analytics.monetization.plans_1_month"))
      expect(response.body).to include(I18n.t("admin.analytics.monetization.exhausted_quotas"))
    end
  end

  describe "GET /admin/analytics/export.csv" do
    let(:regular_user) { create_billing_user!(email: "regular-user@example.com") }

    it "blocks non-admin users with 404" do
      delete destroy_user_session_path
      sign_in_user! regular_user
      get "/admin/analytics/export.csv"
      expect(response).to have_http_status(:not_found)
    end

    it "allows admins to download a CSV file with filtered user events" do
      # Set up events with specific locales
      UserEvent.create!(
        event_type: "workspace_started",
        occurred_at: Time.current,
        locale: "es",
        priority: "low"
      )
      UserEvent.create!(
        event_type: "paywall_viewed",
        occurred_at: Time.current,
        locale: "en",
        priority: "low"
      )

      # Request with es filter
      get "/admin/analytics/export.csv", params: { locale: "es" }

      expect(response).to have_http_status(:ok)
      expect(response.header["Content-Type"]).to include("text/csv")
      expect(response.header["Content-Disposition"]).to include("filename=")
      expect(response.body).to include("workspace_started")
      expect(response.body).not_to include("paywall_viewed")
    end
  end
end
