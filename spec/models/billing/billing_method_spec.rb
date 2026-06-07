# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::BillingMethod, "[REQ-FIT-BILL-001]" do
  describe ".parse" do
    it "accepts card and sinpe" do
      expect(described_class.parse(:card).to_sym).to eq(:card)
      expect(described_class.parse("sinpe").to_sym).to eq(:sinpe)
    end

    it "rejects nil value" do
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /billing_method required/)
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

  describe "equality and hashing" do
    it "implements == and eql? comparison" do
      method1 = described_class.parse(:card)
      method2 = described_class.parse(:card)
      method3 = described_class.parse(:sinpe)

      expect(method1).to eq(method2)
      expect(method1).not_to eq(method3)
      expect(method1).not_to eq(:card)

      expect(method1.eql?(method2)).to be(true)
    end

    it "implements hash function based on value" do
      method1 = described_class.parse(:card)
      method2 = described_class.parse(:card)

      expect(method1.hash).to eq(method2.hash)
    end
  end
end
