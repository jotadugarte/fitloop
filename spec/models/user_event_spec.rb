# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserEvent, "[REQ-FIT-ANALYTICS-001]" do
  let(:valid_attributes) do
    {
      event_type: "workspace_started",
      priority: "low",
      properties: { test: "value" },
      user_id: nil,
      anonymous_session_key: "anon-xyz",
      tab_id: "tab-123",
      project_id: 1,
      nesting_run_id: 1,
      ip: "127.0.0.1",
      user_agent: "Mozilla/5.0",
      country_code: "CR",
      locale: "es",
      idempotency_key: "idemp-xyz",
      occurred_at: Time.current
    }
  end

  subject(:user_event) { described_class.new(valid_attributes) }

  describe "validations" do
    it "is valid with valid attributes" do
      expect(user_event).to be_valid
    end

    it "requires event_type" do
      user_event.event_type = nil
      expect(user_event).not_to be_valid
    end

    it "requires occurred_at" do
      user_event.occurred_at = nil
      expect(user_event).not_to be_valid
    end

    it "requires priority" do
      user_event.priority = nil
      expect(user_event).not_to be_valid
    end

    it "validates uniqueness of idempotency_key when present" do
      described_class.create!(valid_attributes)
      duplicate = described_class.new(valid_attributes)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:idempotency_key]).to include(a_string_matching(/taken|ya está en uso/i))
    end

    it "allows nil or blank idempotency_key multiple times" do
      described_class.create!(valid_attributes.merge(idempotency_key: nil))
      duplicate = described_class.new(valid_attributes.merge(idempotency_key: nil))
      expect(duplicate).to be_valid
    end
  end

  describe "attributes and serialization" do
    it "serializes properties as jsonb/hash" do
      user_event.properties = { foo: "bar" }
      expect(user_event.properties).to eq("foo" => "bar")
    end

    it "has no Active Storage attachments" do
      expect(described_class.attachment_reflections).to be_empty
    end
  end
end
