# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::GapDistanceMm do
  describe ".parse" do
    it "raises ArgumentError when raw is nil" do
      expect { described_class.parse(nil) }.to raise_error(ArgumentError)
    end
  end

  describe "#initialize" do
    it "creates a valid gap distance" do
      expect(described_class.new(5.0).value).to eq(5.0)
    end

    it "raises ArgumentError for negative values" do
      expect { described_class.new(-1.0) }.to raise_error(ArgumentError)
    end
  end

  describe "#silent_tolerable?" do
    it "returns true if value <= 2.0" do
      expect(described_class.new(1.5).silent_tolerable?).to be(true)
      expect(described_class.new(2.0).silent_tolerable?).to be(true)
      expect(described_class.new(2.1).silent_tolerable?).to be(false)
    end
  end

  describe "#warnable?" do
    it "returns true if value > 2.0 and <= 15.0" do
      expect(described_class.new(1.5).warnable?).to be(false)
      expect(described_class.new(5.0).warnable?).to be(true)
      expect(described_class.new(15.0).warnable?).to be(true)
      expect(described_class.new(16.0).warnable?).to be(false)
    end
  end

  describe "#ignored?" do
    it "returns true if value > 15.0" do
      expect(described_class.new(15.0).ignored?).to be(false)
      expect(described_class.new(16.0).ignored?).to be(true)
    end
  end

  describe "#blocking?" do
    it "returns false because gaps >15mm are ignored stray geometry" do
      expect(described_class.new(16.0).blocking?).to be(false)
      expect(described_class.new(5.0).blocking?).to be(false)
    end
  end
end

RSpec.describe Nesting::GapReport do
  describe ".from_json" do
    it "parses json array of hashes" do
      report = described_class.from_json('[{"distance_mm": 5.0}, {"distance_mm": 20.0}]')
      expect(report.gaps.size).to eq(2)
      expect(report.gaps.map(&:value)).to eq([5.0, 20.0])
    end

    it "parses array of hashes directly" do
      report = described_class.from_json([{ "distance_mm" => 5.0 }, { "distance_mm" => 20.0 }])
      expect(report.gaps.size).to eq(2)
      expect(report.gaps.map(&:value)).to eq([5.0, 20.0])
    end
  end

  describe "#unresolved?" do
    it "returns false for ignored gaps regardless of auto_close_gaps" do
      report = described_class.new([Nesting::GapDistanceMm.new(20.0)])
      expect(report.unresolved?(auto_close_gaps: true)).to be(false)
      expect(report.unresolved?(auto_close_gaps: false)).to be(false)
    end

    it "returns false for warnable gaps when auto_close_gaps is true" do
      report = described_class.new([Nesting::GapDistanceMm.new(5.0)])
      expect(report.unresolved?(auto_close_gaps: true)).to be(false)
    end

    it "returns true for warnable gaps when auto_close_gaps is false" do
      report = described_class.new([Nesting::GapDistanceMm.new(5.0)])
      expect(report.unresolved?(auto_close_gaps: false)).to be(true)
    end

    it "returns false for silent gaps regardless of auto_close_gaps" do
      report = described_class.new([Nesting::GapDistanceMm.new(1.5)])
      expect(report.unresolved?(auto_close_gaps: true)).to be(false)
      expect(report.unresolved?(auto_close_gaps: false)).to be(false)
    end

    it "returns true for warnable gaps when ignored gaps also exist" do
      report = described_class.new([
        Nesting::GapDistanceMm.new(14.8),
        Nesting::GapDistanceMm.new(104.3)
      ])
      expect(report.warnable?).to be(true)
      expect(report.unresolved?(auto_close_gaps: false)).to be(true)
      expect(report.unresolved?(auto_close_gaps: true)).to be(false)
    end
  end
end
