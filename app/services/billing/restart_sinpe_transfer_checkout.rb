# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Abandon current SINPE transfer step so checkout can start a new ONVO intent.
  class RestartSinpeTransferCheckout
    REASON = "restarted_sinpe_transfer"

    def self.call(payment:, user:)
      new(payment: payment, user: user).call
    end

    def initialize(payment:, user:)
      @payment = payment
      @user = user
    end

    def call
      raise ArgumentError, "payment required" if @payment.nil?
      raise ArgumentError, "user required" if @user.nil?
      raise ArgumentError, "forbidden" if @payment.user_id != @user.id
      raise ArgumentError, "not_restartable" unless restartable?

      now = Time.current
      @payment.update!(
        superseded_at: now,
        checkout_lock_released_at: now,
        checkout_lock_reason: REASON
      )

      { payment_id: @payment.id }
    end

    private

    def restartable?
      return false unless @payment.sinpe_crc? && @payment.pending? && !@payment.superseded?

      @payment.sinpe_transfer_identification.present? || @payment.sinpe_awaiting_transfer?
    end
  end
end
