# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Integer minor/cent storage for cart snapshots.
  class CentsAmount
    attr_reader :cents, :currency

    def self.parse(cents, currency:)
      raise ArgumentError, "cents required" if cents.nil?

      new(cents.to_i, currency: currency)
    end

    def initialize(cents, currency:)
      @cents = Integer(cents)
      @currency = currency.is_a?(Currency) ? currency : Currency.parse(currency)
      raise ArgumentError, "cents must be non-negative" if @cents.negative?
    end

    def to_i
      @cents
    end

    def to_major
      currency.usd? ? BigDecimal(@cents) / 100 : BigDecimal(@cents)
    end

    def ==(other)
      other.is_a?(self.class) && other.cents == @cents && other.currency == @currency
    end

    alias eql? ==

    def hash
      [ @cents, @currency ].hash
    end
  end
end
