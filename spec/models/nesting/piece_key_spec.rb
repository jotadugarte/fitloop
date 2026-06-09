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
      expect { described_class.parse(nil) }.to raise_error(ArgumentError, /required/)
      expect { described_class.new("") }.to raise_error(ArgumentError, /required/)
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /required/)
      expect { described_class.parse("bad-key") }.to raise_error(ArgumentError, /invalid/)
    end
  end

  describe "equality and hashing" do
    it "compares properly and generates consistent hash" do
      k1 = described_class.parse("42:piece-7")
      k2 = described_class.parse("42:piece-7")
      k3 = described_class.parse("11")
      expect(k1).to eq(k2)
      expect(k1.eql?(k2)).to be(true)
      expect(k1).not_to eq(k3)
      expect(k1.hash).to eq(k2.hash)
    end
  end
end
