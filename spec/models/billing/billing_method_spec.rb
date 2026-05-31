# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::BillingMethod, "[REQ-FIT-BILL-001]" do
  describe ".parse" do
    it "accepts card and sinpe" do
      expect(described_class.parse(:card).to_sym).to eq(:card)
      expect(described_class.parse("sinpe").to_sym).to eq(:sinpe)
    end

    it "rejects unknown methods" do
      expect { described_class.parse("wire") }.to raise_error(ArgumentError)
    end
  end

  describe "#compatible_with_currency?" do
    it "requires crc for sinpe" do
      sinpe = described_class.parse(:sinpe)
      expect(sinpe.compatible_with_currency?(:crc)).to be(true)
      expect(sinpe.compatible_with_currency?(:usd)).to be(false)
    end

    it "allows card with any currency" do
      card = described_class.parse(:card)
      expect(card.compatible_with_currency?(:usd)).to be(true)
      expect(card.compatible_with_currency?(:crc)).to be(true)
    end
  end
end
