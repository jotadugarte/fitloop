# frozen_string_literal: true

module Billing
  class GeoPaymentDefaults
    # [REQ-FIT-BILL-001] Determine country defaults for billing UX.
    #
    # Preconditions:
    # - request responds to #headers
    # Postconditions:
    # - returns a Hash including :country_code (String or nil)
    def self.from_request(request)
      raise ArgumentError, "request must respond to headers" unless request.respond_to?(:headers)

      country_code = request.headers["CF-IPCountry"]
      if country_code.nil? || country_code.strip.empty?
        remote_ip = request.respond_to?(:remote_ip) ? request.remote_ip : nil
        country_code = Billing::GeoLite2.country_code_for_ip(remote_ip)
      end

      defaults = defaults_for_country(country_code)
      {
        country_code: country_code,
        default_currency: defaults.fetch(:currency),
        default_payment_method: defaults.fetch(:payment_method)
      }
    end

    def self.defaults_for_country(country_code)
      return { currency: :crc, payment_method: :sinpe } if country_code == "CR"

      { currency: :usd, payment_method: :card }
    end
    private_class_method :defaults_for_country
  end
end

