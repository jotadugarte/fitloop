# frozen_string_literal: true

module Analytics
  class ResolveCountry
    def self.call(request)
      return nil if request.nil?

      cf_country = request.headers["CF-IPCountry"].presence || request.get_header("HTTP_CF_IPCOUNTRY").presence
      return cf_country.to_s.upcase if cf_country.present?

      ip = request.respond_to?(:remote_ip) ? request.remote_ip : nil
      if ip.present? && defined?(Billing::GeoLite2)
        geo_country = Billing::GeoLite2.country_code_for_ip(ip)
        return geo_country if geo_country.present?
      end

      nil
    end
  end
end
