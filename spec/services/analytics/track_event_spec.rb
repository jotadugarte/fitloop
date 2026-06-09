# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::TrackEvent, "[REQ-FIT-ANALYTICS-001]" do
  # Load ActiveJob test helper to assert job enqueuing
  include ActiveJob::TestHelper

  let(:critical_event) { "nest_completed" }
  let(:low_event) { "workspace_started" }
  let(:user) { User.create!(email: "admin@example.com", name: "Ana", password: "securepass123", password_confirmation: "securepass123", terms_accepted_at: Time.current, terms_version: "v1", time_zone: "America/Costa_Rica") }

  before do
    allow_any_instance_of(User).to receive(:send_on_create_confirmation_instructions)
  end

  describe ".call" do
    context "when event_type is not in the catalog" do
      it "rejects the tracking attempt" do
        expect {
          described_class.call("invalid_event_type")
        }.to raise_error(ArgumentError, /not registered/i)
      end
    end

    context "when required properties are missing" do
      it "rejects the tracking attempt when keys are absent" do
        expect {
          described_class.call(critical_event, properties: { duration_ms: 120 })
        }.to raise_error(ArgumentError, /missing required properties/i)
      end

      it "rejects blank required property values" do
        expect {
          described_class.call(
            "account_deleted",
            properties: { historical_email: "", historical_name: "Ana" }
          )
        }.to raise_error(ArgumentError, /missing required properties.*historical_email/i)
      end
    end

    context "when event is critical priority" do
      it "saves the event synchronously in the database" do
        expect {
          described_class.call(
            critical_event,
            properties: { duration_ms: 120, pieces_count: 5, sheets_used: 1 },
            user_id: user.id,
            occurred_at: Time.current
          )
        }.to change(UserEvent, :count).by(1)

        event = UserEvent.last
        expect(event.event_type).to eq(critical_event)
        expect(event.priority).to eq("critical")
        expect(event.user_id).to eq(user.id)
      end
    end

    context "when event is low priority" do
      it "enqueues a TrackEventJob instead of writing directly" do
        expect {
          described_class.call(
            low_event,
            properties: { test: "data" },
            anonymous_session_key: "session-123"
          )
        }.to have_enqueued_job(TrackEventJob).with(
          low_event,
          hash_including(
            "properties" => { "test" => "data" },
            "anonymous_session_key" => "session-123"
          )
        )

        # Confirm database is NOT updated synchronously
        expect(UserEvent.count).to eq(0)
      end
    end

    context "idempotency key checks" do
      it "prevents duplicate sync insertions for critical events" do
        key = "idemp-key-1"
        attrs = {
          properties: {},
          idempotency_key: key,
          occurred_at: Time.current
        }

        expect {
          described_class.call("payment_succeeded", **attrs)
        }.to change(UserEvent, :count).by(1)

        expect {
          described_class.call("payment_succeeded", **attrs)
        }.not_to change(UserEvent, :count)
      end

      it "drops duplicate critical events when the database raises RecordNotUnique" do
        allow(UserEvent).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique)

        expect(Rails.logger).to receive(:info).with(/Duplicate critical event dropped via unique idempotency_key/)

        expect {
          described_class.call("payment_succeeded", idempotency_key: "dup-db-key")
        }.not_to raise_error
      end

      it "re-raises RecordInvalid errors that are unrelated to idempotency keys" do
        invalid_event = UserEvent.new
        invalid_event.errors.add(:event_type, "is invalid")
        error = ActiveRecord::RecordInvalid.new(invalid_event)
        allow(UserEvent).to receive(:create!).and_raise(error)

        expect {
          described_class.call("payment_succeeded")
        }.to raise_error(ActiveRecord::RecordInvalid)
      end
    end

    context "rate limiting for low-priority events" do
      it "enqueues the job if within limit" do
        expect {
          described_class.call(low_event, anonymous_session_key: "session-rate-1")
        }.to have_enqueued_job(TrackEventJob)
      end

      it "drops the low-priority event if rate limit (300/hour) is exceeded" do
        # Seed 300 events for this session key in the last hour
        300.times do |i|
          UserEvent.create!(
            event_type: low_event,
            priority: "low",
            anonymous_session_key: "session-rate-2",
            occurred_at: Time.current - i.seconds
          )
        end

        # 301st event should be dropped silently (no job enqueued)
        expect {
          described_class.call(low_event, anonymous_session_key: "session-rate-2")
        }.not_to have_enqueued_job(TrackEventJob)
      end

      it "rate limits low-priority events scoped to user_id only" do
        300.times do |i|
          UserEvent.create!(
            event_type: low_event,
            priority: "low",
            user_id: user.id,
            occurred_at: Time.current - i.seconds
          )
        end

        expect {
          described_class.call(low_event, user_id: user.id)
        }.not_to have_enqueued_job(TrackEventJob)
      end

      it "rate limits low-priority events scoped to anonymous_session_key only" do
        300.times do |i|
          UserEvent.create!(
            event_type: low_event,
            priority: "low",
            anonymous_session_key: "anon-only",
            occurred_at: Time.current - i.seconds
          )
        end

        expect {
          described_class.call(low_event, anonymous_session_key: "anon-only")
        }.not_to have_enqueued_job(TrackEventJob)
      end

      it "does not rate limit when neither user_id nor anonymous_session_key is present" do
        300.times do |i|
          UserEvent.create!(
            event_type: low_event,
            priority: "low",
            occurred_at: Time.current - i.seconds
          )
        end

        expect {
          described_class.call(low_event)
        }.to have_enqueued_job(TrackEventJob)
      end

      it "does not rate limit critical events even if threshold is breached" do
        # Seed 300 low-priority events
        300.times do |i|
          UserEvent.create!(
            event_type: low_event,
            priority: "low",
            anonymous_session_key: "session-rate-3",
            occurred_at: Time.current - i.seconds
          )
        end

        # Critical event should still be written synchronously
        expect {
          described_class.call(
            critical_event,
            properties: { duration_ms: 120, pieces_count: 5, sheets_used: 1 },
            anonymous_session_key: "session-rate-3",
            occurred_at: Time.current
          )
        }.to change(UserEvent, :count).by(1)
      end
    end
  end
end
