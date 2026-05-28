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
  end
end

