# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::EventCatalog, "[REQ-FIT-ANALYTICS-001]" do
  describe ".all_event_types" do
    it "matches keys in config/analytics_event_catalog.yml" do
      yaml_events = YAML.load_file(Rails.root.join("config/analytics_event_catalog.yml")).keys

      expect(described_class.all_event_types).to match_array(yaml_events)
    end
  end

  describe ".priority_for" do
    it "returns configured priority for known events" do
      expect(described_class.priority_for("nest_completed")).to eq("critical")
      expect(described_class.priority_for("workspace_started")).to eq("low")
    end

    it "defaults unknown keys to low when not in catalog hash" do
      expect(described_class.priority_for("unknown_event")).to eq("low")
    end
  end

  describe ".required_properties_for" do
    it "returns configured required property names" do
      expect(described_class.required_properties_for("first_dxf_uploaded")).to eq(%w[filename byte_size])
      expect(described_class.required_properties_for("payment_succeeded")).to eq([])
    end
  end
end
