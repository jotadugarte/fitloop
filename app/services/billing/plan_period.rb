# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Plan ends_at = end of natural day N months later in user time zone (D29).
  class PlanPeriod
    def self.ends_at_for(starts_at:, tier_months:, time_zone:)
      zone = ActiveSupport::TimeZone[time_zone] || Time.zone
      anchor = starts_at.in_time_zone(zone)
      end_day = anchor.to_date >> tier_months
      zone.local(end_day.year, end_day.month, end_day.day, 23, 59, 59)
    end
  end
end
