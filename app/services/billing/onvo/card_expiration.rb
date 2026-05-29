# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Parse MM/YY or MM/YYYY card expiration input.
    module CardExpiration
      module_function

      def parse(value)
        raw = value.to_s.strip
        raise ArgumentError, "card_exp required" if raw.empty?

        if (match = raw.match(%r{\A(\d{1,2})\s*/\s*(\d{2,4})\z}))
          month = match[1].to_i
          year = normalize_year(match[2].to_i)
          return { exp_month: month, exp_year: year }
        end

        digits = raw.gsub(/\D/, "")
        if digits.length == 4
          return { exp_month: digits[0, 2].to_i, exp_year: normalize_year(digits[2, 2].to_i) }
        end

        raise ArgumentError, "invalid card_exp"
      end

      def normalize_year(year)
        return year if year >= 100

        current_century = (Time.zone.today.year / 100) * 100
        current_century + year
      end
    end
  end
end
