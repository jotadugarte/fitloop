# frozen_string_literal: true

module Billing
  class GeoPaymentDefaults
    # [REQ-FIT-BILL-001] Determine country defaults for billing UX.
    #
    # Preconditions:
    # - request responds to #headers
    # Postconditions:
    # - returns a Hash including :country_code (String or nil)
    def self.from_request(request, session: nil, user: nil)
      raise ArgumentError, "request must respond to headers" unless request.respond_to?(:headers)

      country_code = country_override
      country_code ||= cloudflare_country_code(request)
      if country_code.nil? || country_code.strip.empty?
        remote_ip = request.respond_to?(:remote_ip) ? request.remote_ip : nil
        country_code = Billing::GeoLite2.country_code_for_ip(remote_ip)
      end
      country_code ||= country_from_user(user)
      country_code ||= session&.dig(:billing_country_code).presence
      country_code = normalize_country(country_code)

      persist_country_code!(session, country_code) if session.respond_to?(:[]=) && country_code.present?

      defaults = defaults_for_country(country_code)
      {
        country_code: country_code,
        default_currency: defaults.fetch(:currency),
        default_payment_method: defaults.fetch(:payment_method),
        available_payment_methods: defaults.fetch(:available_payment_methods)
      }
    end

    def self.cloudflare_country_code(request)
      request.headers["CF-IPCountry"].presence ||
        request.get_header("HTTP_CF_IPCOUNTRY").presence
    end

    def self.country_override
      value = ENV["FITLOOP_BILLING_COUNTRY_OVERRIDE"]
      return nil if value.nil? || value.strip.empty?

      value.strip.upcase
    end

    def self.country_from_user(user)
      return nil unless user.respond_to?(:time_zone)

      zone = user.time_zone.to_s.strip
      return "CR" if zone == "America/Costa_Rica"

      nil
    end

    def self.normalize_country(country_code)
      return nil if country_code.nil?

      stripped = country_code.to_s.strip.upcase
      stripped.empty? ? nil : stripped
    end

    def self.persist_country_code!(session, country_code)
      session[:billing_country_code] = country_code
    end

    def self.defaults_for_country(country_code)
      return { currency: :crc, payment_method: :sinpe, available_payment_methods: [ :sinpe, :card ] } if country_code == "CR"

      { currency: :usd, payment_method: :card, available_payment_methods: [ :card ] }
    end
    private_class_method :defaults_for_country
  end
end
