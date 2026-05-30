# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Single-item cart line (internal); paywall posts here then redirects to checkout.
  class CartUpsert
    def self.call(user:, guest_token:, kind:, nesting_run_id: nil, tier_months: nil, currency_mode:)
      new(
        user: user,
        guest_token: guest_token,
        kind: kind,
        nesting_run_id: nesting_run_id,
        tier_months: tier_months,
        currency_mode: currency_mode
      ).call
    end

    def initialize(user:, guest_token:, kind:, nesting_run_id:, tier_months:, currency_mode:)
      @user = user
      @guest_token = guest_token
      @kind = ProductKind.parse(kind)
      @nesting_run_id = nesting_run_id
      @tier_months = tier_months.nil? ? nil : TierMonths.parse(tier_months)
      @currency = Currency.parse(currency_mode)
    end

    def call
      validate!
      existing = find_existing
      existing&.destroy!
      Cart.create!(cart_attributes)
    end

    private

    def validate!
      @kind.validate_pairing!(nesting_run: @nesting_run_id, tier_months: @tier_months)
      raise ArgumentError, "user or guest_token required" if @user.nil? && @guest_token.blank?
    end

    def find_existing
      if @user
        Cart.find_by(user_id: @user.id)
      else
        Cart.find_by(guest_token: @guest_token)
      end
    end

    def cart_attributes
      list_cents, sinpe_cents = price_cents_pair
      base = {
        kind: @kind.to_s,
        currency_mode: @currency.to_s,
        overage: false,
        list_price_cents: list_cents.to_i,
        sinpe_price_cents: sinpe_cents.to_i
      }

      if @kind.plan?
        base.merge(tier_months: @tier_months.to_i, user_id: @user&.id, guest_token: @user ? nil : @guest_token)
      else
        base.merge(nesting_run_id: @nesting_run_id, user_id: @user&.id, guest_token: @user ? nil : @guest_token)
      end
    end

    def price_cents_pair
      if @kind.plan?
        card_usd, official_crc, sinpe_crc = Pricing.plan_price_triple(@tier_months)
        list = @currency.usd? ? card_usd : official_crc
        sinpe = @currency.usd? ? card_usd : sinpe_crc
      else
        list = @currency.usd? ? Pricing.single_download_official_usd : Pricing.single_download_official_crc
        sinpe = @currency.usd? ? Pricing.single_download_official_usd : Pricing.single_download_sinpe_crc
      end

      [
        CentsAmount.parse(amount_to_cents(list, @currency), currency: @currency),
        CentsAmount.parse(amount_to_cents(sinpe, @currency), currency: @currency)
      ]
    end

    def amount_to_cents(amount, currency)
      currency.usd? ? (amount.to_f * 100).round : amount.to_i
    end
  end
end
