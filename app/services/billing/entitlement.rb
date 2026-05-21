# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-003] Authorizes nested DXF download via grant or active plan quota.
  class Entitlement
    def self.can_download?(user:, nesting_run:, at: Time.current)
      new(user: user, nesting_run: nesting_run, at: at).can_download?
    end

    def initialize(user:, nesting_run:, at: Time.current)
      @user = user
      @nesting_run = nesting_run
      @at = at
    end

    def can_download?
      return false unless @user.billing_ready? && @user.operationally_active?

      grant? || plan_quota?
    end

    private

    def grant?
      DownloadGrant.exists?(user_id: @user.id, nesting_run_id: @nesting_run.id)
    end

    def plan_quota?
      subscription = Subscription.active_at(@at).find_by(user_id: @user.id)
      return false unless subscription

      !QuotaCounter.for(subscription, at: @at).exhausted?
    end
  end
end
