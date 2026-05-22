# frozen_string_literal: true

require "rails_helper"

RSpec.describe PlanMonthlyUsage, "[REQ-FIT-BILL-002]" do
  let(:user) { create_billing_user! }
  let(:subscription) do
    Subscription.create!(
      user: user,
      tier_months: 1,
      starts_at: Time.current,
      ends_at: 1.month.from_now
    )
  end

  describe "associations [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] belongs to subscription" do
      expect(described_class.reflect_on_association(:subscription).macro).to eq(:belongs_to)
    end
  end

  describe "monthly quota [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] defaults quota_limit to 50 downloads per month (D27)" do
      usage = described_class.new(
        subscription: subscription,
        period_year: 2026,
        period_month: 5
      )

      expect(usage.quota_limit).to eq(50)
      expect(usage.downloads_used).to eq(0)
    end

    it "[REQ-FIT-BILL-002] enforces unique period per subscription" do
      described_class.create!(
        subscription: subscription,
        period_year: 2026,
        period_month: 5,
        downloads_used: 1
      )

      duplicate = described_class.new(
        subscription: subscription,
        period_year: 2026,
        period_month: 5
      )

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:period_month, :taken)
    end

    it "[REQ-FIT-BILL-002] rejects downloads_used above quota_limit" do
      usage = described_class.new(
        subscription: subscription,
        period_year: 2026,
        period_month: 6,
        downloads_used: 51,
        quota_limit: 50
      )

      expect(usage).not_to be_valid
      expect(usage.errors).to be_of_kind(:downloads_used, :less_than_or_equal_to)
    end
  end
end
