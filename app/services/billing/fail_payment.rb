# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Marks a payment failed from gateway confirmation.
  class FailPayment
    def self.call(payment:, failure_code: nil, failure_message: nil)
      new(payment: payment, failure_code: failure_code, failure_message: failure_message).call
    end

    def initialize(payment:, failure_code: nil, failure_message: nil)
      @payment = payment
      @failure_code = failure_code
      @failure_message = failure_message
    end

    def call
      return :already_terminal if @payment.failed?

      @payment.update!(
        status: :failed,
        gateway_status: "failed",
        failure_code: @failure_code,
        failure_message: @failure_message
      )
      :failed
    end
  end
end
