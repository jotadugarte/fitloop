# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mis pagos page", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /mis-pagos [REQ-FIT-BILL-002]" do
    it "shows active plan tier, period, and monthly quota hint" do
      zone = ActiveSupport::TimeZone["America/Costa_Rica"]
      starts_at = zone.local(2026, 5, 22, 1, 58, 0)
      ends_at = Billing::PlanPeriod.ends_at_for(
        starts_at: starts_at,
        tier_months: 2,
        time_zone: user.time_zone
      )

      travel_to zone.local(2026, 6, 15, 12, 0, 0) do
        create_active_subscription!(user: user, tier_months: 2, starts_at: starts_at, ends_at: ends_at)

        get mis_pagos_path, params: { locale: "es" }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-testid="mis-pagos-plan-tier"')
        expect(response.body).to include(I18n.t("billing.planes.tier_2", locale: :es))
        expect(response.body).to include(I18n.t("billing.mis_pagos.period_started", locale: :es))
        expect(response.body).to include(I18n.t("billing.mis_pagos.period_ends", locale: :es))
        expect(response.body).to include(I18n.t("billing.mis_pagos.quota_monthly_heading", locale: :es))
        expect(response.body).to include(I18n.t("billing.mis_pagos.quota_monthly_hint", locale: :es))
        expect(response.body).to include("mis-pagos-active-plan")
        expect(response.body).to include("22 de julio de 2026 23:59")
        expect(response.body).not_to include("22 de julio de 2026 05:59")
      end
    end
  end
end
