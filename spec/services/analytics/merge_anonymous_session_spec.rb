# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::MergeAnonymousSession, "[REQ-FIT-ANALYTICS-001]" do
  let(:user) { User.create!(email: "designer@example.com", name: "Designer", password: "securepass123", password_confirmation: "securepass123", terms_accepted_at: Time.current, terms_version: "v1", time_zone: "America/Costa_Rica") }

  before do
    allow_any_instance_of(User).to receive(:send_on_create_confirmation_instructions)

    # Seed some user events
    UserEvent.create!(
      event_type: "workspace_started",
      priority: "low",
      anonymous_session_key: "anon-1",
      user_id: nil,
      occurred_at: Time.current - 10.minutes
    )
    UserEvent.create!(
      event_type: "first_dxf_uploaded",
      priority: "low",
      anonymous_session_key: "anon-1",
      user_id: nil,
      occurred_at: Time.current - 5.minutes
    )
    UserEvent.create!(
      event_type: "workspace_started",
      priority: "low",
      anonymous_session_key: "anon-2",
      user_id: nil,
      occurred_at: Time.current
    )
  end

  describe ".call" do
    it "reassigns user_id for all events matching the anonymous_session_key" do
      expect {
        described_class.call("anon-1", user.id)
      }.to change { UserEvent.where(user_id: user.id).count }.from(0).to(2)

      # Verify the targeted events were updated
      events_anon_1 = UserEvent.where(anonymous_session_key: "anon-1")
      expect(events_anon_1.pluck(:user_id)).to all(eq(user.id))

      # Verify the other anonymous session's events were NOT updated
      event_anon_2 = UserEvent.find_by(anonymous_session_key: "anon-2")
      expect(event_anon_2.user_id).to be_nil
    end

    it "is a no-op if anonymous_session_key is blank" do
      expect {
        described_class.call("", user.id)
      }.not_to change { UserEvent.where(user_id: user.id).count }
    end
  end
end
