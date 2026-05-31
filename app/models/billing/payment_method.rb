# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Checkout/payment rail aligned with Payment.payment_method enum.
  class PaymentMethod
    CONFIG = {
      Payment.payment_methods[:card_usd] => { currency: :usd, card: true },
      Payment.payment_methods[:card_crc] => { currency: :crc, card: true },
      Payment.payment_methods[:sinpe_crc] => { currency: :crc, card: false }
    }.freeze

    ALL = CONFIG.keys.freeze

    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "payment_method required" if raw.nil?

      value = raw.to_s
      raise ArgumentError, "unknown payment_method: #{raw}" unless ALL.include?(value)

      new(value)
    end

    def initialize(value)
      @value = value.to_s
      raise ArgumentError, "unknown payment_method: #{value}" unless CONFIG.key?(@value)
    end

    def to_s
      @value
    end

    def card?
      config.fetch(:card)
    end

    def sinpe?
      @value == Payment.payment_methods[:sinpe_crc]
    end

    def billing_method
      BillingMethod.parse(card? ? :card : :sinpe)
    end

    def currency
      Currency.parse(config.fetch(:currency))
    end

    def ==(other)
      other.is_a?(self.class) && other.value == @value
    end

    alias eql? ==

    def hash
      @value.hash
    end

    private

    def config
      CONFIG.fetch(@value)
    end
  end
end
