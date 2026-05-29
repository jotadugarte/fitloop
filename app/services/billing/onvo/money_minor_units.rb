# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] ONVO payment-intent amount in currency minor units (USD cents, CRC centavos).
    class MoneyMinorUnits
      MINOR_UNIT_FACTOR = 100

      attr_reader :amount, :currency_code

      def self.from_breakdown(breakdown)
        new(breakdown)
      end

      def initialize(breakdown)
        raise ArgumentError, "breakdown required" if breakdown.nil?

        hash = breakdown.is_a?(Hash) ? breakdown : breakdown.to_h
        currency = hash.fetch(:currency)
        total = BigDecimal(hash.fetch(:total_amount).to_s)

        @currency_code = normalize_currency_code(currency)
        @amount = to_minor_units(total, currency)
      end

      def to_i
        amount
      end

      private

      def normalize_currency_code(currency)
        code = currency.to_s.upcase
        return code if %w[USD CRC].include?(code)

        raise ArgumentError, "unsupported currency: #{currency}"
      end

      def to_minor_units(total, currency)
        case currency.to_sym
        when :usd, :crc
          (total * MINOR_UNIT_FACTOR).round(0).to_i
        else
          raise ArgumentError, "unsupported currency: #{currency}"
        end
      end
    end
  end
end
