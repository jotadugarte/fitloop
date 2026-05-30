# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Parsed ONVO webhook payload.
    class WebhookEvent
      attr_reader :type, :payment_intent_id, :raw

      def initialize(payload)
        raise ArgumentError, "payload required" if payload.nil?

        @raw = payload.deep_stringify_keys
        @type = @raw.fetch("type")
        data = @raw.fetch("data")
        @payment_intent_id = data.fetch("id")
      end
    end
  end
end
