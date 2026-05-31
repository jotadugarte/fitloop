# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Bundle for checkout breakdown (currency + payment + geo + IVA).
  class CheckoutContext
    attr_reader :currency, :payment_method, :country_code, :iva_applicable

    def self.from_session(billing_context_hash)
      raise ArgumentError, "billing_context required" if billing_context_hash.nil?

      hash = billing_context_hash.symbolize_keys
      country = hash[:country_code]
      country_vo = country.nil? ? nil : CountryCode.parse(country)

      new(
        currency: hash.fetch(:currency),
        payment_method: hash.fetch(:payment_method),
        country_code: country_vo,
        iva_applicable: hash.fetch(:iva_applicable)
      )
    end

    def initialize(currency:, payment_method:, country_code: nil, iva_applicable:)
      @currency = currency.is_a?(Currency) ? currency : Currency.parse(currency)
      @payment_method = resolve_payment_method(payment_method)
      @country_code = country_code
      @iva_applicable = iva_applicable == true
      validate!
    end

    def to_h
      {
        currency: @currency.to_sym,
        payment_method: @payment_method.to_sym,
        country_code: @country_code&.to_s,
        iva_applicable: @iva_applicable
      }
    end

    private

    def resolve_payment_method(payment_method)
      case payment_method
      when BillingMethod
        raise ArgumentError, "use PaymentMethod or symbol for checkout context"
      when PaymentMethod
        payment_method.billing_method
      when Symbol, String
        BillingMethod.parse(payment_method)
      else
        raise ArgumentError, "invalid payment_method type"
      end
    end

    def validate!
      raise ArgumentError, "payment_method incompatible with currency" unless @payment_method.compatible_with_currency?(@currency)

      if @iva_applicable && !costa_rica?
        raise ArgumentError, "IVA only applicable in Costa Rica"
      end
    end

    def costa_rica?
      @country_code.nil? || @country_code.costa_rica?
    end
  end
end
