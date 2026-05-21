# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth billing 2:30 AM scenarios", type: :system do
  around do |example|
    GoldenFixtures.assert_present!
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  describe "guest pays single download after losing workshop [REQ-FIT-BILL-001] [REQ-FIT-BILL-003]", :slow do
    let(:user) { create_billing_user!(email: "two-thirty@example.com") }

    it "[REQ-FIT-BILL-001] nests as guest, pays, discards workshop, downloads from Mis pagos (D54)" do
      project = setup_golden_nested_project!
      run = project.nesting_runs.order(:id).last

      click_link I18n.t("projects.show.download_nested_dxf")
      expect(page).to have_css('[data-testid="download-paywall"]')

      sign_in user
      visit checkout_path(nesting_run_id: run.id)

      within('[data-testid="checkout-pay-card-usd"]') do
        click_button I18n.t("billing.checkout.simulate_success")
      end

      grant = DownloadGrant.find_by!(user: user, nesting_run: run)
      expect(grant.retained_nested_dxf).to be_attached

      discard_workshop_session!
      expect(Workspace.bound?(page_session)).to be(false)

      visit mis_pagos_path
      expect(page).to have_css('[data-testid="mis-pagos-download"]')

      visit mis_pagos_download_path(grant)
      expect(page.driver.status_code).to eq(200)
      expect(page.driver.response.headers["Content-Disposition"]).to include("attachment")
    end
  end

  describe "plan user cannot re-download after workshop loss [REQ-FIT-BILL-002]", :slow do
    let(:user) { create_billing_user!(email: "plan-user@example.com") }

    before do
      create_active_subscription!(user: user)
    end

    it "[REQ-FIT-BILL-002] blocks nested DXF download after workspace discard (D50)" do
      visit start_project_path
      sign_in user

      project = setup_golden_nested_project!

      expect(page).to have_css('[data-testid="plan-included-download-hint"]')

      discard_workshop_session!
      expect(Project.exists?(project.id)).to be(false)

      visit nested_dxf_project_path(project)

      expect(page).to have_current_path(new_project_path)
      disposition = page.driver.response.headers["Content-Disposition"]
      expect(disposition.to_s).not_to include("attachment")
      expect(page).to have_content(I18n.t("workspace.expired"))
        .or have_content(I18n.t("workspace.tab_closed_expired"))
    end
  end
end
