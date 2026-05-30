# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Valid plan duration (1, 2, or 4 months).
  class TierMonths
    ALLOWED = Subscription::ALLOWED_TIER_MONTHS.freeze

    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "tier_months required" if raw.nil?

      new(raw.to_i)
    end

    def self.from_cart(cart)
      raise ArgumentError, "cart required" if cart.nil?
      raise ArgumentError, "cart has no tier_months" if cart.tier_months.blank?

      parse(cart.tier_months)
    end

    def self.from_record(record)
      raise ArgumentError, "record required" if record.nil?

      parse(record.tier_months)
    end

    def initialize(value)
      @value = Integer(value)
      raise ArgumentError, "invalid tier_months: #{value}" unless ALLOWED.include?(@value)
    end

    def to_i
      @value
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
