# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] User left card checkout before a charge (e.g. canceled 3DS) — not a failed payment.
  class AbandonIncompleteCardCheckout
    REASON = "user_canceled_3ds"

    def self.call(payment:)
      new(payment: payment).call
    end

    def initialize(payment:)
      @payment = payment
    end

    def call
      raise ArgumentError, "payment required" if @payment.nil?
      return :not_card unless card_payment?
      return :already_terminal if @payment.succeeded?
      return :already_abandoned if @payment.checkout_abandoned_at.present?
      return :not_incomplete unless @payment.incomplete_card_checkout_attempt?

      now = Time.current
      attrs = {
        checkout_abandoned_at: now,
        checkout_lock_released_at: now,
        checkout_lock_reason: REASON
      }
      if @payment.failed?
        attrs[:status] = :pending
        attrs[:failure_code] = nil
        attrs[:failure_message] = nil
      end
      @payment.update!(attrs)
      :abandoned
    end

    private

    def card_payment?
      @payment.card_crc? || @payment.card_usd?
    end

  end
end
