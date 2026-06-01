# frozen_string_literal: true

module Analytics
  class TrackEvent
    def self.call(event_type, properties: {}, user_id: nil, anonymous_session_key: nil, tab_id: nil, project_id: nil, nesting_run_id: nil, ip: nil, user_agent: nil, country_code: nil, locale: nil, idempotency_key: nil, occurred_at: nil)
      event_type_str, props = validate!(event_type, properties)
      priority = Analytics::EventCatalog.priority_for(event_type_str)
      occurred_at ||= Time.current

      event_attributes = {
        event_type: event_type_str,
        priority: priority,
        properties: props,
        user_id: user_id,
        anonymous_session_key: anonymous_session_key,
        tab_id: tab_id,
        project_id: project_id,
        nesting_run_id: nesting_run_id,
        ip: ip,
        user_agent: user_agent,
        country_code: country_code,
        locale: locale,
        idempotency_key: idempotency_key,
        occurred_at: occurred_at
      }

      if priority == "critical"
        persist_critical!(event_attributes, idempotency_key)
      else
        return false if rate_limit_exceeded?(user_id, anonymous_session_key)

        TrackEventJob.perform_later(event_type_str, event_attributes.as_json)
      end
      true
    end

    def self.validate!(event_type, properties)
      event_type_str = event_type.to_s
      unless Analytics::EventCatalog.all_event_types.include?(event_type_str)
        raise ArgumentError, "Event type '#{event_type_str}' is not registered in the catalog"
      end

      props = properties.stringify_keys
      missing_props = Analytics::EventCatalog.required_properties_for(event_type_str).reject do |key|
        props[key].present?
      end
      if missing_props.any?
        raise ArgumentError,
              "Event type '#{event_type_str}' missing required properties: #{missing_props.join(', ')}"
      end

      [event_type_str, props]
    end

    def self.persist_critical!(event_attributes, idempotency_key)
      UserEvent.create!(event_attributes)
    rescue ActiveRecord::RecordNotUnique
      Rails.logger.info "[analytics] Duplicate critical event dropped via unique idempotency_key: #{idempotency_key}"
    rescue ActiveRecord::RecordInvalid => e
      if e.record.errors.of_kind?(:idempotency_key, :taken)
        Rails.logger.info "[analytics] Duplicate critical event dropped via model uniqueness validation on idempotency_key: #{idempotency_key}"
      else
        raise e
      end
    end

    private_class_method :persist_critical!

    def self.rate_limit_exceeded?(user_id, anonymous_session_key)
      limit = Analytics::Thresholds.low_priority_events_per_hour
      scope = UserEvent.where("occurred_at >= ?", 1.hour.ago).where(priority: "low")

      if user_id.present? && anonymous_session_key.present?
        scope = scope.where("user_id = ? OR anonymous_session_key = ?", user_id, anonymous_session_key)
      elsif user_id.present?
        scope = scope.where(user_id: user_id)
      elsif anonymous_session_key.present?
        scope = scope.where(anonymous_session_key: anonymous_session_key)
      else
        return false
      end

      scope.count >= limit
    end
  end
end
