# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PlanExpiryPreview, "[REQ-FIT-BILL-002]" do
  include BillingModelHelpers

  describe ".projected_ends_at [REQ-FIT-BILL-002]" do
    it "[REQ-FIT-BILL-002] projects plan expiry from now when user has no active subscription (D28)" do
      user = create_billing_user!

      projected = described_class.projected_ends_at(user: user, tier_months: 1, now: Time.utc(2026, 5, 1, 12, 0, 0))

      expect(projected).to be_a(Time)
      expect(projected).to be > Time.utc(2026, 5, 1, 12, 0, 0)
    end
  end
end
