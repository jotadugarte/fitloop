# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::AssignNestingParameters, "[REQ-FIT-DOM-001]" do
  describe ".call" do
    it "returns kerf and margin value objects for valid params" do
      result = described_class.call(raw_params: { kerf_mm: 2.5, margin_mm: 8 })

      expect(result).to be_ok
      expect(result.kerf).to eq(Nesting::KerfMm.parse(2.5))
      expect(result.margin).to eq(Nesting::MarginMm.parse(8))
      expect(result.errors).to eq([])
    end

    it "rejects negative kerf" do
      result = described_class.call(raw_params: { kerf_mm: -0.1, margin_mm: 5 })

      expect(result).not_to be_ok
      expect(result.errors.first).to match(/non-negative/)
    end

    it "rejects negative margin" do
      result = described_class.call(raw_params: { kerf_mm: 1, margin_mm: -1 })

      expect(result).not_to be_ok
      expect(result.errors.first).to match(/non-negative/)
    end

    it "rejects nil kerf or margin" do
      result = described_class.call(raw_params: { kerf_mm: nil, margin_mm: 5 })

      expect(result).not_to be_ok
      expect(result.errors.first).to match(/required/)
    end

    it "rejects non-numeric kerf" do
      result = described_class.call(raw_params: { kerf_mm: "abc", margin_mm: 5 })

      expect(result).not_to be_ok
      expect(result.errors.first).to be_present
    end
  end
end
