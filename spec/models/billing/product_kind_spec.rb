# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::ProductKind, "[REQ-FIT-BILL-001]" do
  describe ".parse" do
    it "accepts single_download and plan" do
      expect(described_class.parse("single_download").single_download?).to be(true)
      expect(described_class.parse(:plan).plan?).to be(true)
    end

    it "rejects unknown kinds" do
      expect { described_class.parse("subscription") }.to raise_error(ArgumentError)
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
end
