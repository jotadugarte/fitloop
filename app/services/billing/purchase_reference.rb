# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Human-facing 12-digit reference for single-download payments.
  class PurchaseReference
    DIGITS = 12
    MAX = 10**DIGITS

    def self.generate
      loop do
        reference = format("%0#{DIGITS}d", SecureRandom.random_number(MAX))
        return reference unless Payment.exists?(purchase_reference: reference)
      end
    end
  end
end
