# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RecordPlanDownload, "[REQ-FIT-BILL-002]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Quota", status: :completed) }
  let(:nesting_run) { project.nesting_runs.create!(status: "completed") }

  it "[REQ-FIT-BILL-002] increments monthly usage for plan-quota downloads (D27)" do
    subscription = create_active_subscription!(user: user)

    described_class.call(user: user, nesting_run: nesting_run)

    usage = PlanMonthlyUsage.find_by!(subscription: subscription)
    expect(usage.downloads_used).to eq(1)
  end

  it "[REQ-FIT-BILL-002] skips increment when download uses a signed token" do
    create_active_subscription!(user: user)

    described_class.call(user: user, nesting_run: nesting_run, via_download_token: true)

    expect(PlanMonthlyUsage.count).to eq(0)
  end

  it "[REQ-FIT-BILL-002] skips increment when single-purchase grant covers the run" do
    subscription = create_active_subscription!(user: user)
    DownloadGrant.create!(
      user: user,
      nesting_run: nesting_run,
      kind: "single_purchase",
      retained_until: 1.day.from_now
    )

    described_class.call(user: user, nesting_run: nesting_run)

    usage = PlanMonthlyUsage.find_by!(subscription: subscription)
    expect(usage.downloads_used).to eq(0)
  end
end
