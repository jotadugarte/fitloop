# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CountryCode, "[REQ-FIT-BILL-001]" do
  describe ".parse" do
    it "normalizes case and whitespace" do
      expect(described_class.parse(" cr ").to_s).to eq("CR")
    end

    it "returns nil for blank input" do
      expect(described_class.parse(nil)).to be_nil
      expect(described_class.parse("  ")).to be_nil
    end

    it "rejects garbage" do
      expect { described_class.parse("COSTA RICA") }.to raise_error(ArgumentError)
      expect { described_class.parse("X") }.to raise_error(ArgumentError)
    end
  end

  describe "#costa_rica?" do
    it "identifies CR" do
      expect(described_class.parse("CR").costa_rica?).to be(true)
      expect(described_class.parse("US").costa_rica?).to be(false)
    end
  end

  describe ".from_geo_defaults" do
    it "reads country_code from geo hash" do
      code = described_class.from_geo_defaults(country_code: "us")
      expect(code.to_s).to eq("US")
    end

    it "returns nil when geo has no country" do
      expect(described_class.from_geo_defaults(country_code: nil)).to be_nil
    end
  end
end
