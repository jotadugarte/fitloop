# frozen_string_literal: true

class TrackEventJob < ApplicationJob
  queue_as :analytics

  def perform(event_type, attributes)
    begin
      UserEvent.create!(attributes)
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.info "[analytics] Duplicate low-priority event dropped via unique idempotency_key: #{attributes['idempotency_key']}"
    rescue ActiveRecord::RecordInvalid => e
      if e.record.errors.of_kind?(:idempotency_key, :taken)
        Rails.logger.info "[analytics] Duplicate low-priority event dropped via model uniqueness validation on idempotency_key: #{attributes['idempotency_key']}"
      else
        raise e
      end
    end
  end
end
