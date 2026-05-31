# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::KerfMm, "[REQ-FIT-NEST-002]" do
  describe ".parse" do
    it "accepts zero and positive values" do
      expect(described_class.parse(0).to_f).to eq(0.0)
      expect(described_class.parse(2.5).to_f).to eq(2.5)
    end

    it "rejects nil and negative values" do
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /required/)
      expect { described_class.parse(-0.1) }.to raise_error(ArgumentError, /non-negative/)
    end
  end

  describe "equality" do
    it "does not equal MarginMm with the same numeric value" do
      kerf = described_class.parse(1.0)
      margin = Nesting::MarginMm.parse(1.0)

      expect(kerf).not_to eq(margin)
    end
  end
end

RSpec.describe Nesting::MarginMm, "[REQ-FIT-NEST-002]" do
  describe ".parse" do
    it "accepts zero and positive values" do
      expect(described_class.parse(5).to_f).to eq(5.0)
    end

    it "rejects nil and negative values" do
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /required/)
      expect { described_class.parse(-1) }.to raise_error(ArgumentError, /non-negative/)
    end
  end
end
