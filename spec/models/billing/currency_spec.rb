# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Currency, "[REQ-FIT-BILL-001]" do
  describe ".parse" do
    it "accepts usd and crc" do
      expect(described_class.parse(:usd).to_sym).to eq(:usd)
      expect(described_class.parse("crc").to_sym).to eq(:crc)
    end

    it "returns existing Currency value objects unchanged" do
      currency = described_class.parse(:usd)

      expect(described_class.parse(currency)).to equal(currency)
    end

    it "rejects unknown currencies" do
      expect { described_class.parse("eur") }.to raise_error(ArgumentError)
      expect { described_class.parse(nil) }.to raise_error(ArgumentError)
    end
  end

  describe "#compatible_with_payment_method?" do
    it "matches payment method currency" do
      usd = described_class.parse(:usd)
      expect(usd.compatible_with_payment_method?("card_usd")).to be(true)
      expect(usd.compatible_with_payment_method?("sinpe_crc")).to be(false)
    end
  end
end
