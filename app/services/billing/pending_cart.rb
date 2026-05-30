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
      @kind = parse_kind(data.fetch("kind"))
      @currency = Currency.parse(data.fetch("currency_mode"))
      @nesting_run_id = data["nesting_run_id"]
      @tier_months = data["tier_months"].present? ? TierMonths.parse(data["tier_months"]) : nil
      validate!
    end

    attr_reader :nesting_run_id, :tier_months

    def kind
      @kind.to_s
    end

    def currency_mode
      @currency.to_s
    end

    def to_h
      {
        "kind" => kind,
        "nesting_run_id" => nesting_run_id,
        "tier_months" => tier_months&.to_i,
        "currency_mode" => currency_mode
      }
    end

    def plan?
      @kind.plan?
    end

    private

    def parse_kind(raw)
      ProductKind.parse(raw)
    rescue ArgumentError
      raise ArgumentError, "invalid kind"
    end

    def validate!
      if plan?
        raise ArgumentError, "tier_months required" if @tier_months.nil?
      else
        raise ArgumentError, "nesting_run_id required" if nesting_run_id.blank?
      end
    end
  end
end
