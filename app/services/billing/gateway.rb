# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Billing gateway selection via BILLING_GATEWAY ENV.
  class Gateway
    SIMULATE = "simulate"
    ONVO = "onvo"

    def self.mode
      ENV.fetch("BILLING_GATEWAY", SIMULATE).to_s
    end

    def self.simulate?
      !onvo?
    end

    def self.onvo?
      mode == ONVO
    end
  end
end
