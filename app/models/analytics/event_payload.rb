# frozen_string_literal: true

module Analytics
  # Value object boundary for Analytics::TrackEvent ingestion.
  class EventPayload
    attr_reader :event_type, :properties, :user_id, :anonymous_session_key, :tab_id,
                :project_id, :nesting_run_id, :ip, :user_agent, :country_code,
                :locale, :idempotency_key, :occurred_at

    def self.from_kwargs(event_type, properties: {}, user_id: nil, anonymous_session_key: nil,
                         tab_id: nil, project_id: nil, nesting_run_id: nil, ip: nil,
                         user_agent: nil, country_code: nil, locale: nil,
                         idempotency_key: nil, occurred_at: nil)
      new(
        event_type: event_type,
        properties: properties,
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
      )
    end

    def initialize(event_type:, properties: {}, user_id: nil, anonymous_session_key: nil,
                   tab_id: nil, project_id: nil, nesting_run_id: nil, ip: nil,
                   user_agent: nil, country_code: nil, locale: nil,
                   idempotency_key: nil, occurred_at: nil)
      @event_type = EventType.parse(event_type)
      @properties = properties.stringify_keys
      validate_required_properties!

      @user_id = user_id
      @anonymous_session_key = anonymous_session_key
      @tab_id = tab_id
      @project_id = project_id
      @nesting_run_id = nesting_run_id
      @ip = ip
      @user_agent = user_agent
      @country_code = country_code
      @locale = locale
      @idempotency_key = idempotency_key
      @occurred_at = occurred_at
    end

    def priority
      EventCatalog.priority_for(@event_type.to_s)
    end

    def to_event_attributes
      {
        event_type: @event_type.to_s,
        priority: priority,
        properties: @properties,
        user_id: @user_id,
        anonymous_session_key: @anonymous_session_key,
        tab_id: @tab_id,
        project_id: @project_id,
        nesting_run_id: @nesting_run_id,
        ip: @ip,
        user_agent: @user_agent,
        country_code: @country_code,
        locale: @locale,
        idempotency_key: @idempotency_key,
        occurred_at: @occurred_at || Time.current
      }
    end

    private

    def validate_required_properties!
      missing = EventCatalog.required_properties_for(@event_type.to_s).reject do |key|
        @properties[key].present?
      end
      return if missing.empty?

      raise ArgumentError,
            "Event type '#{@event_type}' missing required properties: #{missing.join(', ')}"
    end
  end
end
