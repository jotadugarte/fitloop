# frozen_string_literal: true

module Analytics
  # Resolves user/session context for nest_completed telemetry from pre-nest project events.
  class NestTelemetryContext
    def self.from(project:, nesting_run:)
      primary_anchor = nesting_run.started_at || nesting_run.created_at
      event = find_event(project, primary_anchor)
      fallback_anchor = nesting_run.finished_at || Time.current
      event ||= find_event(project, fallback_anchor) if fallback_anchor > primary_anchor
      new(event)
    end

    def self.find_event(project, anchor)
      UserEvent.where(project_id: project.id)
               .where("occurred_at <= ?", anchor)
               .order(occurred_at: :desc)
               .first
    end

    private_class_method :find_event

    def initialize(event)
      @event = event
    end

    def user_id
      @event&.user_id
    end

    def anonymous_session_key
      @event&.anonymous_session_key
    end

    def tab_id
      @event&.tab_id
    end

    def ip
      @event&.ip
    end

    def user_agent
      @event&.user_agent
    end

    def country_code
      @event&.country_code
    end

    def locale
      @event&.locale || I18n.default_locale.to_s
    end
  end
end
