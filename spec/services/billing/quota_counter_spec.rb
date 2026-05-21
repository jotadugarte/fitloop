# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::QuotaCounter, "[REQ-FIT-BILL-002]", type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }
  let(:subscription) do
    create_active_subscription!(
      user: user,
      tier_months: 4,
      starts_at: Time.zone.parse("2026-01-01"),
      ends_at: Time.zone.parse("2026-12-31 23:59:59")
    )
  end

  it "[REQ-FIT-BILL-002] allocates 50 downloads per calendar month slice (D27)" do
    march = Time.zone.parse("2026-03-10 12:00:00")
    counter = described_class.for(subscription, at: march)

    expect(counter.usage.quota_limit).to eq(50)
    expect(counter.usage.period_year).to eq(2026)
    expect(counter.usage.period_month).to eq(3)
    expect(counter.remaining).to eq(50)

    50.times { counter.record_download! }

    expect(counter).to be_exhausted
  end

  it "[REQ-FIT-BILL-002] resets quota in a new calendar month within the same subscription (D27)" do
    travel_to Time.zone.parse("2026-03-28") do
      counter = described_class.for(subscription)
      50.times { counter.record_download! }
      expect(counter).to be_exhausted
    end

    travel_to Time.zone.parse("2026-04-02") do
      april = described_class.for(subscription)
      expect(april).not_to be_exhausted
      expect(april.usage.period_month).to eq(4)
      expect(april.remaining).to eq(50)
    end
  end
end
