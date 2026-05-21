# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Tracks 50 downloads per calendar month within a subscription (D27).
  class QuotaCounter
    def self.for(subscription, at: Time.current)
      new(subscription, at: at)
    end

    def initialize(subscription, at: Time.current)
      @subscription = subscription
      @at = at
    end

    def usage
      @usage ||= PlanMonthlyUsage.find_or_create_by!(
        subscription: @subscription,
        period_year: @at.year,
        period_month: @at.month
      )
    end

    def remaining
      usage.quota_limit - usage.downloads_used
    end

    def exhausted?
      remaining <= 0
    end

    def record_download!
      usage.increment!(:downloads_used)
    end
  end
end
