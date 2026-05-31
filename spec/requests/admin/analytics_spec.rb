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
end
