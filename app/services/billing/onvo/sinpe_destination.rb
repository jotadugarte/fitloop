# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] ONVO SINPE Móvil transfer destination shown at checkout.
    class SinpeDestination
      DEFAULT_NUMBER = "+506 70196686"
      DEFAULT_HOLDER_NAME = "ONVO Pay"

      def self.number
        from_config("number") || DEFAULT_NUMBER
      end

      def self.holder_name
        from_config("holder_name") || DEFAULT_HOLDER_NAME
      end

      def self.to_h
        { number: number, holder_name: holder_name }
      end

      def self.from_config(key)
        raw = Billing::Pricing.config_section("onvo_sinpe_destination")
        raw[key]&.to_s&.strip.presence
      end
      private_class_method :from_config
    end
  end
end
