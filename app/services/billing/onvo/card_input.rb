# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Normalize and validate Fitloop card checkout fields before ONVO API calls.
    class CardInput
      HOLDER_NAME_MIN = 2
      HOLDER_NAME_MAX = 100
      CARD_NUMBER_MIN = 13
      CARD_NUMBER_MAX = 19

      def self.parse!(holder_name:, card_number:, card_exp:, cvv:)
        new(holder_name: holder_name, card_number: card_number, card_exp: card_exp, cvv: cvv).parse!
      end

      def initialize(holder_name:, card_number:, card_exp:, cvv:)
        @holder_name = holder_name.to_s.strip
        @card_number = card_number.to_s.gsub(/[\s-]/, "")
        @card_exp = card_exp.to_s.strip
        @cvv = cvv.to_s.gsub(/\s/, "")
      end

      def parse!
        validate_holder_name!
        validate_card_number!
        expiration = CardExpiration.parse(@card_exp)
        validate_not_expired!(expiration.fetch(:exp_month), expiration.fetch(:exp_year))
        validate_cvv!

        {
          holder_name: @holder_name,
          card_number: @card_number,
          exp_month: expiration.fetch(:exp_month),
          exp_year: expiration.fetch(:exp_year),
          cvv: @cvv
        }
      end

      private

      def validate_holder_name!
        raise ArgumentError, "holder_name_invalid" if @holder_name.length < HOLDER_NAME_MIN
        raise ArgumentError, "holder_name_invalid" if @holder_name.length > HOLDER_NAME_MAX
        return if @holder_name.match?(/\A[\p{L}\s'.-]+\z/u)

        raise ArgumentError, "holder_name_invalid"
      end

      def validate_card_number!
        raise ArgumentError, "card_number_invalid" unless @card_number.match?(/\A[0-9]+\z/)
        raise ArgumentError, "card_number_invalid" unless @card_number.length.between?(CARD_NUMBER_MIN, CARD_NUMBER_MAX)
        raise ArgumentError, "card_number_invalid" unless luhn_valid?(@card_number)
        raise ArgumentError, "card_number_test_only" if onvo_test_mode? && !TestCardNumbers.include?(@card_number)
      end

      def onvo_test_mode?
        ENV.fetch("ONVO_MODE", "test") == "test"
      end

      def validate_cvv!
        raise ArgumentError, "card_cvv_invalid" unless @cvv.match?(/\A\d{3,4}\z/)
      end

      def validate_not_expired!(month, year)
        last_valid_day = Date.new(year, month, -1)
        raise ArgumentError, "card_exp_expired" if last_valid_day < Time.zone.today
      end

      def luhn_valid?(number)
        digits = number.chars.reverse.map(&:to_i)
        sum = digits.each_with_index.sum do |digit, index|
          if index.odd?
            doubled = digit * 2
            doubled > 9 ? doubled - 9 : doubled
          else
            digit
          end
        end
        (sum % 10).zero?
      end
    end
  end
end
