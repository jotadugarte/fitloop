# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::EventType, "[REQ-FIT-ANALYTICS-001]" do
  describe ".parse" do
    it "returns a value object for catalog event types" do
      event_type = described_class.parse("workspace_started")

      expect(event_type.to_s).to eq("workspace_started")
      expect(event_type).to eq(described_class.parse("workspace_started"))
    end

    it "rejects blank values" do
      expect { described_class.parse("") }.to raise_error(ArgumentError, /event_type required/i)
    end

    it "rejects unknown event types" do
      expect { described_class.parse("not_in_catalog") }.to raise_error(ArgumentError, /not registered/i)
    end
  end

  describe "equality and hashing" do
    it "compares properly and generates consistent hash" do
      type1 = described_class.parse("workspace_started")
      type2 = described_class.parse("workspace_started")
      type3 = described_class.parse("nest_completed")

      expect(type1).to eq(type2)
      expect(type1.eql?(type2)).to be(true)
      expect(type1).not_to eq(type3)
      expect(type1.hash).to eq(type2.hash)
    end
  end
end
