# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Consumes one plan monthly download when serving nested DXF (D27).
  class RecordPlanDownload
    def self.call(user:, nesting_run:, at: Time.current)
      new(user: user, nesting_run: nesting_run, at: at).call
    end

    def initialize(user:, nesting_run:, at: Time.current)
      @user = user
      @nesting_run = nesting_run
      @at = at
    end

    def call
      entitlement = Entitlement.new(user: @user, nesting_run: @nesting_run, at: @at)
      return unless entitlement.plan_quota?
      return if entitlement.single_purchase_grant?

      subscription = Subscription.active_at(@at).find_by(user_id: @user.id)
      return unless subscription

      QuotaCounter.for(subscription, at: @at).record_download!
    end
  end
end
