# frozen_string_literal: true

module Billing
  class PaymentSelection
    # [REQ-FIT-BILL-001]
    # Currency is forced by country (CR → CRC, international → USD).
    # Payment method may be chosen when available (SINPE only in CR).
    def self.resolve(request:, session:, user: nil)
      raise ArgumentError, "session must support []" unless session.respond_to?(:[])

      policy = RegionalPolicy.from_request(request: request, session: session, user: user)
      payment_method = parse_payment_method(session[:billing_payment_method])
      payment_method = policy.fetch(:default_payment_method) unless policy.fetch(:available_payment_methods).include?(payment_method)

      {
        country_code: policy.fetch(:country_code),
        currency: policy.fetch(:currency),
        payment_method: payment_method,
        iva_applicable: policy.fetch(:iva_applicable),
        iva_rate: policy.fetch(:iva_rate),
        available_payment_methods: policy.fetch(:available_payment_methods)
      }
    end

    def self.parse_currency(value)
      case value
      when "usd", :usd then :usd
      when "crc", :crc then :crc
      else nil
      end
    end

    def self.parse_payment_method(value)
      case value
      when "card", :card then :card
      when "sinpe", :sinpe then :sinpe
      else nil
      end
    end
  end
end
