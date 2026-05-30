# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Parse MM/YY card expiration (slash required after normalization).
    module CardExpiration
      module_function

      def parse(value)
        raw = normalize(value)
        raise ArgumentError, "card_exp_invalid" if raw.empty?

        match = raw.match(%r{\A(\d{2})/(\d{2})\z})
        raise ArgumentError, "card_exp_invalid" unless match

        month = match[1].to_i
        year = normalize_year(match[2].to_i)
        raise ArgumentError, "card_exp_invalid" unless month.between?(1, 12)

        { exp_month: month, exp_year: year }
      end

      def normalize(value)
        stripped = value.to_s.strip
        return stripped if stripped.include?("/")

        digits = stripped.gsub(/\D/, "")
        return "" if digits.empty?
        return "#{digits[0, 2]}/#{digits[2, 2]}" if digits.length == 4

        stripped
      end

      def normalize_year(year)
        return year if year >= 100

        current_century = (Time.zone.today.year / 100) * 100
        current_century + year
      end
    end
  end
end
