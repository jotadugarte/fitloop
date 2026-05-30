# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] ONVO sandbox SINPE Móvil numbers (docs.onvopay.com payments/testing#sinpe-móvil).
    module TestSinpeMobileNumbers
      LOCAL_NUMBERS = %w[
        88888888
        88884444
        88889521
        88883333
      ].freeze

      module_function

      def include?(number)
        LOCAL_NUMBERS.include?(normalize_local(number))
      end

      def normalize_local(number)
        digits = number.to_s.gsub(/\D/, "")
        return digits[-8, 8] if digits.length > 8

        digits
      end
    end
  end
end
