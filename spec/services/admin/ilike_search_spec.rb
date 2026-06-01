# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::IlikeSearch, "[REQ-FIT-ANALYTICS-001]" do
  describe ".escape" do
    it "escapes ILIKE wildcard characters" do
      expect(described_class.escape("100%")).to eq("100\\%")
      expect(described_class.escape("a_b")).to eq("a\\_b")
      expect(described_class.escape("back\\slash")).to eq("back\\\\slash")
    end
  end

  describe ".pattern" do
    it "wraps escaped terms with percent wildcards" do
      expect(described_class.pattern("100%")).to eq("%100\\%%")
    end
  end
end
