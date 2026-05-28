# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::GeoPaymentDefaults, "[REQ-FIT-BILL-001]" do
  describe ".from_request [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] prefers CF-IPCountry when present (D16)" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })

      defaults = described_class.from_request(request)

      expect(defaults.fetch(:country_code)).to eq("CR")
    end
  end
end

