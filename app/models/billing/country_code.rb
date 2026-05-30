# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] ISO 3166-1 alpha-2 billing country.
  class CountryCode
    FORMAT = /\A[A-Z]{2}\z/

    attr_reader :value

    def self.parse(raw)
      return nil if raw.nil?

      stripped = raw.to_s.strip.upcase
      return nil if stripped.empty?

      new(stripped)
    end

    def self.from_geo_defaults(geo_hash)
      raise ArgumentError, "geo_hash required" if geo_hash.nil?

      parse(geo_hash[:country_code] || geo_hash["country_code"])
    end

    def initialize(value)
      @value = value.to_s.upcase
      raise ArgumentError, "invalid country_code: #{value}" unless @value.match?(FORMAT)
    end

    def to_s
      @value
    end

    def costa_rica?
      @value == RegionalPolicy::COSTA_RICA
    end

    def ==(other)
      other.is_a?(self.class) && other.value == @value
    end

    alias eql? ==

    def hash
      @value.hash
    end
  end
end
