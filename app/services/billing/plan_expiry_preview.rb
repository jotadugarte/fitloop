# frozen_string_literal: true

module Billing
  class PlanExpiryPreview
    # [REQ-FIT-BILL-002]
    # Preconditions:
    # - user responds to #time_zone and #subscriptions
    # - tier_months is an Integer
    # - now is a Time
    # Postconditions:
    # - returns a Time representing projected ends_at
    def self.projected_ends_at(user:, tier_months:, now: Time.current)
      raise ArgumentError, "tier_months must be an Integer" unless tier_months.is_a?(Integer)
      raise ArgumentError, "now must be a Time" unless now.is_a?(Time)

      existing = Subscription.where(user_id: user.id).active_at(now).order(ends_at: :desc).first
      starts_at = existing ? existing.ends_at : now
      Billing::PlanPeriod.ends_at_for(starts_at: starts_at, tier_months: tier_months, time_zone: user.time_zone)
    end
  end
end
