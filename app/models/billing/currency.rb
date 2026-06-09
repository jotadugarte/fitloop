# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Billing currency mode (usd | crc).
  class Currency
    ALLOWED = %i[usd crc].freeze

    attr_reader :value

    def self.parse(raw)
      return raw if raw.is_a?(Currency)

      raise ArgumentError, "currency required" if raw.nil?

      new(raw)
    end

    def initialize(raw)
      @value = raw.to_s.downcase.to_sym
      raise ArgumentError, "invalid currency: #{raw}" unless ALLOWED.include?(@value)
    end

    def to_sym
      @value
    end

    def to_s
      @value.to_s
    end

    def usd?
      @value == :usd
    end

    def crc?
      @value == :crc
    end

    def compatible_with_payment_method?(payment_method)
      method = payment_method.is_a?(PaymentMethod) ? payment_method : PaymentMethod.parse(payment_method)
      method.currency == self
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
