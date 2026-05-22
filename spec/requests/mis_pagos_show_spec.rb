# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mis pagos page", type: :request do
  let(:user) { create_billing_user! }

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /mis-pagos [REQ-FIT-BILL-002]" do
    it "shows active plan tier, period, and monthly quota hint" do
      starts_at = Time.zone.parse("2026-05-01 10:00:00")
      ends_at = Time.zone.parse("2026-07-22 05:59:00")
      create_active_subscription!(user: user, tier_months: 2, starts_at: starts_at, ends_at: ends_at)

      get mis_pagos_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="mis-pagos-plan-tier"')
      expect(response.body).to include(I18n.t("billing.planes.tier_2"))
      expect(response.body).to include(I18n.t("billing.mis_pagos.period_started"))
      expect(response.body).to include(I18n.t("billing.mis_pagos.period_ends"))
      expect(response.body).to include(I18n.t("billing.mis_pagos.quota_monthly_heading"))
      expect(response.body).to include(I18n.t("billing.mis_pagos.quota_monthly_hint"))
      expect(response.body).to include("mis-pagos-active-plan")
    end
  end
end
