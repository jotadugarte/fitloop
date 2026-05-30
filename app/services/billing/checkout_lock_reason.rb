# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Branded checkout lock release / supersede reasons persisted on Payment.
  class CheckoutLockReason
    TIMEOUT = "timeout"
    USER_ABANDONED = "user_abandoned"
    SUPERSEDED = "superseded"
    USER_CANCELED_3DS = "user_canceled_3ds"

    ALL = [ TIMEOUT, USER_ABANDONED, SUPERSEDED, USER_CANCELED_3DS ].freeze

    def self.valid?(value)
      ALL.include?(value.to_s)
    end
  end
end
