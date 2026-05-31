# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Pricing axis (:card | :sinpe) — distinct from full PaymentMethod.
  class BillingMethod
    ALLOWED = %i[card sinpe].freeze

    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "billing_method required" if raw.nil?

      new(raw)
    end

    def initialize(raw)
      @value = raw.to_s.downcase.to_sym
      raise ArgumentError, "invalid billing_method: #{raw}" unless ALLOWED.include?(@value)
    end

    def to_sym
      @value
    end

    def card?
      @value == :card
    end

    def sinpe?
      @value == :sinpe
    end

    def compatible_with_currency?(currency)
      curr = currency.is_a?(Currency) ? currency : Currency.parse(currency)
      return true if card?

      curr.crc?
    end

    def ==(other)
      other.is_a?(self.class) && other.value == @value
    end

    alias eql? ==

    def hash
      @value.hash
    end
  end
end
