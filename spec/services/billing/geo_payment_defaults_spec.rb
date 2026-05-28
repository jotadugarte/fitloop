# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::GeoPaymentDefaults, "[REQ-FIT-BILL-001]" do
  describe ".from_request [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] prefers CF-IPCountry when present (D16)" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })

      defaults = described_class.from_request(request)

      expect(defaults.fetch(:country_code)).to eq("CR")
    end

    it "[REQ-FIT-BILL-001] falls back to GeoLite2 lookup when CF-IPCountry is missing (D16)" do
      request = instance_double(ActionDispatch::Request, headers: {}, remote_ip: "1.2.3.4")
      allow(Billing::GeoLite2).to receive(:country_code_for_ip).with("1.2.3.4").and_return("US")

      defaults = described_class.from_request(request)

      expect(defaults.fetch(:country_code)).to eq("US")
    end

    it "[REQ-FIT-BILL-001] defaults to CRC+SINPE for CR and USD+card outside CR (D3, D16)" do
      request_cr = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      defaults_cr = described_class.from_request(request_cr)
      expect(defaults_cr.fetch(:default_currency)).to eq(:crc)
      expect(defaults_cr.fetch(:default_payment_method)).to eq(:sinpe)

      request_us = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "US" })
      defaults_us = described_class.from_request(request_us)
      expect(defaults_us.fetch(:default_currency)).to eq(:usd)
      expect(defaults_us.fetch(:default_payment_method)).to eq(:card)
    end

    it "[REQ-FIT-BILL-001] does not offer SINPE outside CR (D29)" do
      request_us = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "US" })
      defaults_us = described_class.from_request(request_us)

      expect(defaults_us.fetch(:available_payment_methods)).to eq([ :card ])
    end
  end
end

