# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Manual abandon of SINPE pending checkout — releases workshop lock locally (no FailPayment).
  class ReleasePendingCheckoutLock
    REASON = CheckoutLockReason::USER_ABANDONED

    def self.call(payment:, user:)
      new(payment: payment, user: user).call
    end

    def initialize(payment:, user:)
      @payment = payment
      @user = user
    end

    def call
      assert_inputs!
      return :already_released if lock_already_released?

      now = Time.current
      @payment.update!(
        checkout_abandoned_at: now,
        checkout_lock_released_at: now,
        checkout_lock_reason: REASON
      )
      :released
    end

    private

    def assert_inputs!
      raise ArgumentError, "payment required" if @payment.nil?
      raise ArgumentError, "user required" if @user.nil?
      raise ArgumentError, "payment must be persisted" unless @payment.persisted?
      return if @payment.user_id == @user.id

      raise ArgumentError, "payment does not belong to user"
    end

    def lock_already_released?
      @payment.checkout_lock_released_at.present?
    end
  end
end
