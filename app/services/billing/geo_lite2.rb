# frozen_string_literal: true

require "ipaddr"
require "maxminddb"

module Billing
  # [REQ-FIT-BILL-001] GeoLite2 Country MMDB lookup (fallback when CF-IPCountry is absent).
  class GeoLite2
    class << self
      # @return [String, nil] ISO 3166-1 alpha-2 country code (e.g. "CR", "US")
      def country_code_for_ip(ip)
        return nil unless ip.is_a?(String) && !ip.strip.empty?
        return nil if private_or_loopback?(ip)

        result = client&.lookup(ip.strip)
        return nil unless result&.found?

        result.country&.iso_code
      rescue StandardError
        nil
      end

      def available?
        client.present?
      end

      def database_path
        ENV["GEOLITE2_COUNTRY_MMDB_PATH"].to_s.strip.presence
      end

      private

      def client
        return @client if defined?(@client)

        path = database_path
        @client = (path && File.file?(path) ? MaxMindDB.new(path) : nil)
      end

      def private_or_loopback?(ip)
        addr = IPAddr.new(ip.strip)
        addr.loopback? || addr.private?
      rescue IPAddr::InvalidAddressError
        true
      end
    end
  end
end
