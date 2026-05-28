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
      { country_code: country_code }
    end
  end
end

