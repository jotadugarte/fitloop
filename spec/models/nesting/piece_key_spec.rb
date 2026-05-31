# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::PieceKey, "[REQ-FIT-SPLIT-001]" do
  describe ".parse" do
    it "accepts index and fingerprint formats" do
      expect(described_class.parse("42:piece-7").to_s).to eq("42:piece-7")
      expect(described_class.parse("42:fp-0123456789abcdef").to_s).to eq("42:fp-0123456789abcdef")
      expect(described_class.parse("11").to_s).to eq("11")
    end

    it "rejects blank and invalid formats" do
      expect { described_class.parse("") }.to raise_error(ArgumentError, /required/)
      expect { described_class.parse("bad-key") }.to raise_error(ArgumentError, /invalid/)
    end
  end
end
