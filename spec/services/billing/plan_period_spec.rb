# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PlanPeriod, "[REQ-FIT-BILL-002]" do
  let(:zone) { ActiveSupport::TimeZone["America/Costa_Rica"] }

  it "[REQ-FIT-BILL-002] ends at 23:59:59 on the anchor calendar day in user time zone (D29)" do
    starts_at = zone.local(2026, 5, 22, 1, 58, 0)
    ends_at = described_class.ends_at_for(
      starts_at: starts_at,
      tier_months: 2,
      time_zone: "America/Costa_Rica"
    )

    expect(ends_at).to be_within(1.second).of(zone.local(2026, 7, 22, 23, 59, 59))
    expect(ends_at.utc.hour).to eq(5)
    expect(ends_at.in_time_zone("America/Costa_Rica").hour).to eq(23)
  end

  it "[REQ-FIT-BILL-002] extends from prior ends_at in user zone (D28)" do
    prior_end = zone.local(2026, 6, 20, 23, 59, 59)
    ends_at = described_class.ends_at_for(
      starts_at: prior_end,
      tier_months: 2,
      time_zone: "America/Costa_Rica"
    )

    expect(ends_at).to be_within(1.second).of(zone.local(2026, 8, 20, 23, 59, 59))
  end
end
