# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Major-unit monetary amount with currency.
  class Money
    attr_reader :amount, :currency

    def self.from_cents(cents, currency)
      CentsAmount.parse(cents, currency: currency).to_money
    end

    def self.from_major(amount, currency)
      raise ArgumentError, "amount required" if amount.nil?

      curr = currency.is_a?(Currency) ? currency : Currency.parse(currency)
      decimal = BigDecimal(amount.to_s)
      raise ArgumentError, "amount must be non-negative" if decimal.negative?

      new(decimal, curr)
    end

    def self.from_breakdown_field(hash, key)
      raise ArgumentError, "hash required" if hash.nil?

      from_major(hash.fetch(key), hash.fetch(:currency))
    end

    def initialize(amount, currency)
      @amount = BigDecimal(amount.to_s)
      @currency = currency.is_a?(Currency) ? currency : Currency.parse(currency)
      raise ArgumentError, "amount must be non-negative" if @amount.negative?
    end

    def +(other)
      raise ArgumentError, "currency mismatch" unless other.is_a?(self.class) && other.currency == @currency

      self.class.new(@amount + other.amount, @currency)
    end

    def to_s
      format("%.2f #{@currency}", @amount)
    end

    def ==(other)
      other.is_a?(self.class) && other.amount == @amount && other.currency == @currency
    end

    alias eql? ==

    def hash
      [@amount, @currency].hash
    end
  end
end

module Billing
  class CentsAmount
    def to_money
      Money.from_major(to_major, currency)
    end
  end
end
