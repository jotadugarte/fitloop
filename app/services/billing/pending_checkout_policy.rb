# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] SINPE pending checkout workshop lock window from billing.yml.
  class PendingCheckoutPolicy
    DEFAULT_WORKSHOP_LOCK_MINUTES = 15

    class << self
      def workshop_lock_minutes
        raw = Pricing.config_section("onvo_pending_checkout")["workshop_lock_minutes"]
        minutes = raw.to_i
        minutes.positive? ? minutes : DEFAULT_WORKSHOP_LOCK_MINUTES
      end

      def lock_expires_at(payment)
        assert_payment!(payment)

        payment.created_at + workshop_lock_minutes.minutes
      end

      def lock_active?(payment)
        assert_payment!(payment)
        return false if lock_released?(payment)

        Time.current < lock_expires_at(payment)
      end

      private

      def assert_payment!(payment)
        raise ArgumentError, "payment required" if payment.nil?
        raise ArgumentError, "payment must be persisted" unless payment.persisted?
      end

      def lock_released?(payment)
        payment.respond_to?(:checkout_lock_released_at) && payment.checkout_lock_released_at.present?
      end
    end
  end
end
