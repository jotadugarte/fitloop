# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Validated replace-confirm payload stored in session[:pending_cart].
  class PendingCart
    def self.from_session(raw)
      return nil if raw.blank?

      new(raw)
    end

    def initialize(attrs)
      data = attrs.stringify_keys
      @kind = data.fetch("kind").to_s
      @currency_mode = data.fetch("currency_mode").to_s
      @nesting_run_id = data["nesting_run_id"]
      @tier_months = data["tier_months"]
      validate!
    end

    attr_reader :kind, :currency_mode, :nesting_run_id, :tier_months

    def to_h
      {
        "kind" => kind,
        "nesting_run_id" => nesting_run_id,
        "tier_months" => tier_months,
        "currency_mode" => currency_mode
      }
    end

    def plan?
      kind == Cart.kinds[:plan]
    end

    private

    def validate!
      raise ArgumentError, "invalid kind" unless Cart.kinds.key?(kind)
      raise ArgumentError, "invalid currency_mode" unless Cart.currency_modes.key?(currency_mode)

      if plan?
        raise ArgumentError, "tier_months required" unless Subscription::ALLOWED_TIER_MONTHS.include?(tier_months.to_i)
      else
        raise ArgumentError, "nesting_run_id required" if nesting_run_id.blank?
      end
    end
  end
end
