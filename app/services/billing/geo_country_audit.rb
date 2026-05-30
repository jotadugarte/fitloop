# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Production observability for billing country resolution.
  class GeoCountryAudit
    THROTTLE_TTL = 5.minutes
    BILLING_PATH_PATTERN = %r{\A/(taller/descarga-pago|checkout|carrito|planes|mis-pagos)}.freeze

    class << self
      def record_resolution!(request:, country_code:, source:)
        return unless Rails.env.production?
        return unless billing_related_request?(request)
        return if GeoPaymentDefaults.country_override.present?
        return if GeoPaymentDefaults.cloudflare_country_code(request).present?

        warn_throttled(
          "billing.geo.cf_ipcountry_missing",
          build_missing_cloudflare_message(country_code: country_code, source: source)
        )
      end

      private

      def billing_related_request?(request)
        path = request.path.to_s
        BILLING_PATH_PATTERN.match?(path)
      end

      def build_missing_cloudflare_message(country_code:, source:)
        parts = [
          "[billing.geo] CF-IPCountry missing on #{source_label(source)};",
          "resolved country=#{country_code.inspect}."
        ]
        unless GeoLite2.available?
          parts << "Install GeoLite2 Country MMDB at GEOLITE2_COUNTRY_MMDB_PATH"
          parts << "(see docs/DEPLOY.md) or proxy traffic through Cloudflare."
        end
        parts.join(" ")
      end

      def source_label(source)
        case source
        when :override then "FITLOOP_BILLING_COUNTRY_OVERRIDE"
        when :cloudflare then "CF-IPCountry"
        when :geolite2 then "GeoLite2"
        when :user_time_zone then "user time_zone"
        when :session then "session billing_country_code"
        else "default (international USD)"
        end
      end

      def warn_throttled(cache_key, message)
        return if Rails.cache.read(cache_key)

        Rails.cache.write(cache_key, true, expires_in: THROTTLE_TTL)
        Rails.logger.warn(message)
      end
    end
  end
end
