# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::ProductKind, "[REQ-FIT-BILL-001]" do
  describe ".parse" do
    it "accepts single_download and plan" do
      expect(described_class.parse("single_download").single_download?).to be(true)
      expect(described_class.parse(:plan).plan?).to be(true)
    end

    it "rejects nil value" do
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /product kind required/)
    end

    it "rejects unknown kinds" do
      expect { described_class.parse("subscription") }.to raise_error(ArgumentError)
    end
  end

  describe ".from_cart" do
    it "rejects nil cart" do
      expect { described_class.from_cart(nil) }.to raise_error(ArgumentError, /cart required/)
    end

    it "parses kind from cart object" do
      cart = double("Cart", kind: "single_download")
      expect(described_class.from_cart(cart).single_download?).to be(true)
    end
  end

  describe "#validate_pairing!" do
    it "requires nesting_run for single_download" do
      kind = described_class.parse("single_download")
      expect { kind.validate_pairing!(nesting_run: nil) }.to raise_error(ArgumentError)
      expect(kind.validate_pairing!(nesting_run: double(present?: true))).to be(true)
    end

    it "requires tier_months for plan" do
      kind = described_class.parse("plan")
      expect { kind.validate_pairing!(tier_months: nil) }.to raise_error(ArgumentError)
      expect(kind.validate_pairing!(tier_months: 1)).to be(true)
    end
  end

  describe "equality and hashing" do
    it "implements == and eql? comparison" do
      kind1 = described_class.parse("plan")
      kind2 = described_class.parse("plan")
      kind3 = described_class.parse("single_download")

      expect(kind1).to eq(kind2)
      expect(kind1).not_to eq(kind3)
      expect(kind1).not_to eq("plan")

      expect(kind1.eql?(kind2)).to be(true)
    end

    it "implements hash function based on value" do
      kind1 = described_class.parse("plan")
      kind2 = described_class.parse("plan")

      expect(kind1.hash).to eq(kind2.hash)
    end
  end
end
