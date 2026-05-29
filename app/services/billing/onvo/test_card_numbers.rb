# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] ONVO sandbox card numbers (docs.onvopay.com payments/testing).
    module TestCardNumbers
      NUMBERS = %w[
        4242424242424242
        4000000000003220
        5555555555554444
        378282246310005
        4000000000000002
        4000000000000127
        4000000000000119
        4111111111111111
      ].freeze

      module_function

      def include?(number)
        NUMBERS.include?(number.to_s.gsub(/\D/, ""))
      end

      def primary_visa
        "4242424242424242"
      end
    end
  end
end
