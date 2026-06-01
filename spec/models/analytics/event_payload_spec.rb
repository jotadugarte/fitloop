# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::EventPayload, "[REQ-FIT-ANALYTICS-001]" do
  describe ".from_kwargs" do
    it "builds a payload with catalog-validated event type and properties" do
      payload = described_class.from_kwargs(
        "nest_completed",
        properties: { duration_ms: 100, pieces_count: 2, sheets_used: 1 },
        user_id: 42,
        anonymous_session_key: "anon-1",
        tab_id: "tab-1"
      )

      expect(payload.event_type.to_s).to eq("nest_completed")
      expect(payload.priority).to eq("critical")
      expect(payload.properties).to eq(
        "duration_ms" => 100,
        "pieces_count" => 2,
        "sheets_used" => 1
      )
    end

    it "rejects missing required properties" do
      expect {
        described_class.from_kwargs("nest_completed", properties: { duration_ms: 100 })
      }.to raise_error(ArgumentError, /missing required properties/i)
    end
  end

  describe "#to_event_attributes" do
    it "maps payload fields for persistence" do
      occurred = Time.zone.parse("2026-05-31 12:00:00")
      payload = described_class.from_kwargs(
        "workspace_started",
        user_id: 7,
        occurred_at: occurred
      )

      expect(payload.to_event_attributes).to include(
        event_type: "workspace_started",
        priority: "low",
        user_id: 7,
        occurred_at: occurred
      )
    end
  end
end
