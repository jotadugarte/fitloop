# frozen_string_literal: true

module Billing
  class PaymentSelection
    # [REQ-FIT-BILL-001]
    # Preconditions:
    # - request responds to #headers
    # - session is a Hash-like object
    # Postconditions:
    # - returns :currency and :payment_method as Symbols
    def self.resolve(request:, session:)
      raise ArgumentError, "session must be a Hash" unless session.is_a?(Hash)

      currency = parse_currency(session[:billing_currency])
      payment_method = parse_payment_method(session[:billing_payment_method])

      if currency && payment_method
        return { currency: currency, payment_method: payment_method }
      end

      defaults = Billing::GeoPaymentDefaults.from_request(request)
      {
        currency: defaults.fetch(:default_currency),
        payment_method: defaults.fetch(:default_payment_method)
      }
    end

    def self.parse_currency(value)
      case value
      when "usd", :usd then :usd
      when "crc", :crc then :crc
      else nil
      end
    end
    private_class_method :parse_currency

    def self.parse_payment_method(value)
      case value
      when "card", :card then :card
      when "sinpe", :sinpe then :sinpe
      else nil
      end
    end
    private_class_method :parse_payment_method
  end
end

