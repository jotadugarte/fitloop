# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] What is being purchased (single_download | plan).
  class ProductKind
    ALLOWED = Cart.kinds.keys.map(&:to_s).freeze

    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "product kind required" if raw.nil?

      new(raw)
    end

    def self.from_cart(cart)
      raise ArgumentError, "cart required" if cart.nil?

      parse(cart.kind)
    end

    def initialize(raw)
      @value = raw.to_s
      raise ArgumentError, "invalid product kind: #{raw}" unless ALLOWED.include?(@value)
    end

    def to_s
      @value
    end

    def single_download?
      @value == Cart.kinds[:single_download]
    end

    def plan?
      @value == Cart.kinds[:plan]
    end

    def validate_pairing!(nesting_run: nil, tier_months: nil)
      has_run = nesting_run.present?
      has_tier = tier_months.present?
      raise ArgumentError, "single_download requires nesting_run" if single_download? && !has_run
      raise ArgumentError, "plan requires tier_months" if plan? && !has_tier
      raise ArgumentError, "invalid product pairing" if has_run && has_tier

      true
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
