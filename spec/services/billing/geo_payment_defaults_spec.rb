# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::GeoPaymentDefaults, "[REQ-FIT-BILL-001]" do
  describe ".from_request [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] prefers CF-IPCountry when present (D16)" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      allow(request).to receive(:get_header).and_return(nil)

      defaults = described_class.from_request(request)

      expect(defaults.fetch(:country_code)).to eq("CR")
    end

    it "[REQ-FIT-BILL-001] falls back to GeoLite2 lookup when CF-IPCountry is missing (D16)" do
      request = instance_double(ActionDispatch::Request, headers: {}, remote_ip: "1.2.3.4", path: "/")
      allow(request).to receive(:get_header).and_return(nil)
      allow(Billing::GeoLite2).to receive(:country_code_for_ip).with("1.2.3.4").and_return("US")

      defaults = described_class.from_request(request)

      expect(defaults.fetch(:country_code)).to eq("US")
      expect(defaults.fetch(:resolution_source)).to eq(:geolite2)
    end

    it "[REQ-FIT-BILL-001] defaults to CRC+SINPE for CR and USD+card outside CR (D3, D16)" do
      request_cr = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      allow(request_cr).to receive(:get_header).and_return(nil)
      defaults_cr = described_class.from_request(request_cr)
      expect(defaults_cr.fetch(:default_currency)).to eq(:crc)
      expect(defaults_cr.fetch(:default_payment_method)).to eq(:sinpe)

      request_us = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "US" })
      allow(request_us).to receive(:get_header).and_return(nil)
      defaults_us = described_class.from_request(request_us)
      expect(defaults_us.fetch(:default_currency)).to eq(:usd)
      expect(defaults_us.fetch(:default_payment_method)).to eq(:card)
    end

    it "[REQ-FIT-BILL-001] does not offer SINPE outside CR (D29)" do
      request_us = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "US" })
      allow(request_us).to receive(:get_header).and_return(nil)
      defaults_us = described_class.from_request(request_us)

      expect(defaults_us.fetch(:available_payment_methods)).to eq([ :card ])
    end

    it "[REQ-FIT-BILL-001] allows FITLOOP_BILLING_COUNTRY_OVERRIDE over CF-IPCountry (D16)" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("FITLOOP_BILLING_COUNTRY_OVERRIDE").and_return("CR")

      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "US" })
      allow(request).to receive(:get_header).and_return(nil)
      defaults = described_class.from_request(request)

      expect(defaults.fetch(:country_code)).to eq("CR")
      expect(defaults.fetch(:default_currency)).to eq(:crc)
      expect(defaults.fetch(:default_payment_method)).to eq(:sinpe)
    end

    it "[REQ-FIT-BILL-001] infers CR from user time_zone when geo is unavailable (D16)" do
      request = instance_double(ActionDispatch::Request, headers: {}, remote_ip: "127.0.0.1")
      allow(request).to receive(:get_header).and_return(nil)
      user = instance_double(User, time_zone: "America/Costa_Rica")

      defaults = described_class.from_request(request, user: user)

      expect(defaults.fetch(:country_code)).to eq("CR")
      expect(defaults.fetch(:default_currency)).to eq(:crc)
    end

    it "[REQ-FIT-BILL-001] persists resolved country in session for later requests (D16)" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      allow(request).to receive(:get_header).and_return(nil)
      session = {}

      described_class.from_request(request, session: session)

      expect(session[:billing_country_code]).to eq("CR")
    end
  end
end
