# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] SINPE pending checkout workshop lock duration from billing.yml.
  class WorkshopLockWindow
    def self.from_config
      new(minutes: PendingCheckoutPolicy.workshop_lock_minutes)
    end

    def initialize(minutes:)
      @minutes = minutes.to_i
      raise ArgumentError, "minutes must be positive" unless @minutes.positive?
    end

    attr_reader :minutes

    def lock_expires_at(payment)
      raise ArgumentError, "payment required" if payment.nil?

      payment.created_at + @minutes.minutes
    end
  end
end
