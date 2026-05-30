# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Country-driven currency and IVA rules (CR vs international).
  class RegionalPolicy
    IVA_RATE = BigDecimal("0.13")
    COSTA_RICA = "CR"

    class << self
      def from_request(request:, session: nil, user: nil)
        geo = GeoPaymentDefaults.from_request(request, session: session, user: user)
        for_country(geo.fetch(:country_code))
      end

      def for_country(country_code)
        code_vo = CountryCode.parse(country_code)
        code = code_vo&.to_s
        costa_rica = code == COSTA_RICA

        {
          country_code: code,
          currency: costa_rica ? :crc : :usd,
          iva_applicable: costa_rica,
          iva_rate: costa_rica ? IVA_RATE : BigDecimal("0"),
          available_payment_methods: costa_rica ? %i[sinpe card] : %i[card],
          default_payment_method: costa_rica ? :sinpe : :card
        }
      end

      private

      def normalize_country(country_code)
        CountryCode.parse(country_code)&.to_s
      end
    end
  end
end
