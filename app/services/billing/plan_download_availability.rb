# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Whether nested DXF download is covered by active plan quota (D33).
  class PlanDownloadAvailability
    def self.plan_included?(user:, at: Time.current)
      new(user: user, at: at).plan_included?
    end

    def self.single_download_checkout_allowed?(user:, at: Time.current)
      new(user: user, at: at).single_download_checkout_allowed?
    end

    def initialize(user:, at: Time.current)
      @user = user
      @at = at
    end

    def plan_included?
      return false unless @user&.operationally_active? && @user.billing_ready?

      subscription = Subscription.active_at(@at).find_by(user_id: @user.id)
      return false unless subscription

      !QuotaCounter.for(subscription, at: @at).exhausted?
    end

    def single_download_checkout_allowed?
      !plan_included?
    end
  end
end
