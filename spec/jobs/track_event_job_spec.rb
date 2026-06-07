# frozen_string_literal: true

require "rails_helper"

RSpec.describe TrackEventJob, type: :job do
  describe "#perform" do
    let(:attributes) do
      {
        "event_type" => "workspace_started",
        "idempotency_key" => SecureRandom.hex(16),
        "occurred_at" => Time.current,
        "priority" => "low",
        "anonymous_session_key" => SecureRandom.hex(16),
        "properties" => { "some" => "data" }
      }
    end

    it "creates a UserEvent successfully" do
      expect {
        described_class.perform_now("workspace_started", attributes)
      }.to change(UserEvent, :count).by(1)
    end

    it "rescues ActiveRecord::RecordNotUnique and drops duplicate" do
      described_class.perform_now("workspace_started", attributes)

      allow(Rails.logger).to receive(:info)
      # Trigger record not unique by calling create! directly on mock/stub or simulating it
      allow(UserEvent).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique.new("duplicate key"))

      expect {
        described_class.perform_now("workspace_started", attributes)
      }.not_to change(UserEvent, :count)

      expect(Rails.logger).to have_received(:info).with(a_string_matching(/Duplicate low-priority event dropped via unique idempotency_key/))
    end

    it "rescues ActiveRecord::RecordInvalid with idempotency_key taken" do
      described_class.perform_now("workspace_started", attributes)

      # Build a record with duplicate key validation error
      invalid_record = UserEvent.new(attributes)
      invalid_record.errors.add(:idempotency_key, :taken)
      allow(UserEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid_record))

      allow(Rails.logger).to receive(:info)

      expect {
        described_class.perform_now("workspace_started", attributes)
      }.not_to change(UserEvent, :count)

      expect(Rails.logger).to have_received(:info).with(a_string_matching(/Duplicate low-priority event dropped via model uniqueness validation/))
    end

    it "raises ActiveRecord::RecordInvalid for other validations" do
      invalid_record = UserEvent.new(attributes)
      invalid_record.errors.add(:event_type, :blank)
      allow(UserEvent).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(invalid_record))

      expect {
        described_class.perform_now("workspace_started", attributes)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
