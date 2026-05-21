# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Consumes one plan monthly download when serving nested DXF (D27).
  class RecordPlanDownload
    def self.call(user:, nesting_run:, at: Time.current, via_download_token: false)
      new(user: user, nesting_run: nesting_run, at: at, via_download_token: via_download_token).call
    end

    def initialize(user:, nesting_run:, at: Time.current, via_download_token: false)
      @user = user
      @nesting_run = nesting_run
      @at = at
      @via_download_token = via_download_token
    end

    def call
      return if @via_download_token

      entitlement = Entitlement.new(user: @user, nesting_run: @nesting_run, at: @at)
      return unless entitlement.plan_quota?
      return if entitlement.single_purchase_grant?

      subscription = Subscription.active_at(@at).find_by(user_id: @user.id)
      return unless subscription

      QuotaCounter.for(subscription, at: @at).record_download!
    end
  end
end
