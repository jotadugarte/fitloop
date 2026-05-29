# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mis pagos page", "[REQ-FIT-BILL-001] [REQ-FIT-BILL-002]", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /mis-pagos [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] shows checkout success notice after ONVO payment_succeeded redirect" do
      get mis_pagos_path, params: { payment_succeeded: 1, locale: "es" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("billing.checkout.success_retention", locale: :es))
    end

    it "[REQ-FIT-BILL-001] shows pending payment banner without processing link" do
      project = Project.create!(ephemeral: true, title: "Mis pagos lock", status: :completed)
      run = project.nesting_runs.create!(status: "completed")
      Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_mis_pagos_lock",
        onvo_mode: "test",
        gateway_status: "processing"
      )

      get mis_pagos_path, params: { locale: "es" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="pending-payment-lock-banner"')
      expect(response.body).to include(I18n.t("billing.checkout.pending_workshop_lock.title", locale: :es))
      expect(response.body).not_to include('data-testid="pending-payment-lock-processing-link"')
      expect(response.body).not_to include("context=workshop")
      expect(response.body).to include('data-testid="mis-pagos-pending-download-row"')
      expect(response.body).to include("mis-pagos-list__item--pending-download")
      expect(response.body).to include('data-testid="mis-pagos-download-pending"')
      expect(response.body).to include(I18n.t("billing.mis_pagos.awaiting_confirmation", locale: :es))
      expect(response.body).to include('data-testid-mis-pagos-pending-sync="true"')
      expect(response.body).not_to include('data-testid="mis-pagos-download"')
    end

    it "[REQ-FIT-BILL-001] hides pending banner when grant exists but payment row still pending" do
      project = Project.create!(ephemeral: true, title: "Stale pending", status: :completed)
      run = project.nesting_runs.create!(status: "completed")
      Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_stale_pending",
        onvo_mode: "test",
        gateway_status: "processing"
      )
      DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: :single_purchase,
        retained_until: 1.day.from_now
      )

      get mis_pagos_path, params: { locale: "es" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-testid="pending-payment-lock-banner"')
      expect(response.body).not_to include('data-testid-mis-pagos-pending-sync="true"')
    end
  end

  describe "GET /mis-pagos [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] shows active plan tier, period, and monthly quota hint" do
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
        expect(response.body).to include(download_paywall_workshop_path)
        expect(response.body).not_to include('href="/checkout"')
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
