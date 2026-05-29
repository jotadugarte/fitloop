# frozen_string_literal: true

module Billing
  # Minimal GeoLite2 wrapper for billing defaults (D16).
  # In v1 we keep this dependency-free and allow tests to stub it.
  class GeoLite2
    # Preconditions:
    # - ip is a String or nil
    # Postconditions:
    # - returns a 2-letter country code String (e.g. "CR") or nil
    def self.country_code_for_ip(ip)
      return nil unless ip.is_a?(String) && !ip.strip.empty?

      nil
    end
  end
end

