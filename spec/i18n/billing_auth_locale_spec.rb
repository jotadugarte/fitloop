# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Billing and auth locale keys", "[REQ-FIT-BILL-001] [REQ-FIT-BILL-002] [REQ-FIT-AUTH-002]" do
  BILLING_AUTH_KEYS = %w[
    billing.single_download.retention_24h
    billing.paywall.title
    billing.paywall.intro
    billing.paywall.aside.title
    billing.paywall.aside.lead
    billing.paywall.aside.benefit_ready
    billing.paywall.aside.benefit_plan
    billing.paywall.aside.benefit_retention
    billing.checkout.demo_badge
    billing.checkout.success_retention
    billing.download.plan_included
    billing.download.retention_expired
    billing.mis_pagos.title
    billing.mis_pagos.download
    billing.planes.title
    billing.planes.success
    billing.suspended
    auth.nav.sign_in
    auth.nav.sign_up
    auth.nav.payments
    auth.registration.terms_label
    workspace.tab_closed_expired
  ].freeze

  LOCALES = %i[en es es_panic].freeze

  LOCALES.each do |locale|
    context "locale #{locale}" do
      around { |example| I18n.with_locale(locale) { example.run } }

      BILLING_AUTH_KEYS.each do |key|
        it "[REQ-FIT-BILL-001] resolves #{key}" do
          translation = I18n.t(key)
          expect(translation).to be_present
          expect(translation).not_to start_with("translation missing")
        end
      end
    end
  end
end
