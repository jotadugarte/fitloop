# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Normalize and validate Fitloop SINPE checkout fields before ONVO API calls.
    class SinpeInput
      IDENTIFICATION_MIN = 9
      IDENTIFICATION_MAX = 12
      MOBILE_NUMBER_LEN = 8

      def self.parse!(identification:, mobile_number:)
        new(identification: identification, mobile_number: mobile_number).parse!
      end

      def initialize(identification:, mobile_number:)
        @identification = digits_only(identification)
        @mobile_number = digits_only(mobile_number)
      end

      def parse!
        validate_identification!
        validate_mobile_number!

        {
          identification: @identification,
          mobile_number: @mobile_number
        }
      end

      private

      def validate_identification!
        length = @identification.length
        return if length >= IDENTIFICATION_MIN && length <= IDENTIFICATION_MAX

        raise ArgumentError, "sinpe_identification_invalid"
      end

      def validate_mobile_number!
        raise ArgumentError, "sinpe_mobile_number_invalid" unless @mobile_number.length == MOBILE_NUMBER_LEN
        return unless onvo_test_mode?
        return if TestSinpeMobileNumbers.include?(@mobile_number)

        raise ArgumentError, "sinpe_mobile_number_test_only"
      end

      def onvo_test_mode?
        ENV.fetch("ONVO_MODE", "test").to_s == "test" && Billing::Gateway.onvo?
      end

      def digits_only(value)
        value.to_s.gsub(/\D/, "")
      end
    end
  end
end
