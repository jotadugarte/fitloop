# frozen_string_literal: true

require "rails_helper"

RSpec.describe Subscription, "[REQ-FIT-BILL-002]" do
  let(:user) { create_billing_user! }

  describe "associations [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] belongs to user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "[REQ-FIT-BILL-002] has many plan monthly usages" do
      expect(described_class.reflect_on_association(:plan_monthly_usages).macro).to eq(:has_many)
    end
  end

  describe "plan tiers [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] allows tiers of 1, 2, and 4 months only (D4)" do
      expect(described_class.new(
        user: user,
        tier_months: 1,
        starts_at: Time.current,
        ends_at: 1.month.from_now
      )).to be_valid

      expect(described_class.new(
        user: user,
        tier_months: 3,
        starts_at: Time.current,
        ends_at: 3.months.from_now
      )).not_to be_valid
    end

    it "[REQ-FIT-BILL-002] requires ends_at after starts_at" do
      subscription = described_class.new(
        user: user,
        tier_months: 2,
        starts_at: Time.current,
        ends_at: 1.day.ago
      )

      expect(subscription).not_to be_valid
      expect(subscription.errors).to be_of_kind(:ends_at, :greater_than)
    end
  end

  describe "active_at? and active_at scope [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] checks if subscription is active at a given time" do
      subscription = described_class.create!(
        user: user,
        tier_months: 1,
        starts_at: 1.day.ago,
        ends_at: 1.day.from_now
      )

      expect(subscription.active_at?(Time.current)).to be true
      expect(subscription.active_at?(2.days.ago)).to be false
      expect(subscription.active_at?(2.days.from_now)).to be false

      expect(described_class.active_at(Time.current)).to include(subscription)
      expect(described_class.active_at(2.days.ago)).not_to include(subscription)
    end
  end
end
