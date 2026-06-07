# frozen_string_literal: true

module Nesting
  # [REQ-FIT-UI-005] Resolve progress_message for the active locale (stored text may be frozen).
  class LocalizedProgressMessage
    KNOWN_KEYS = (
      ProgressSnapshot::PHASE_I18N_KEYS.values + %w[
        nesting.phase.queued
        nesting.phase.preparing
        nesting.completed
        nesting.partial
        nesting.failed
        nesting.cancelled
        nesting.time_limit_notice
        nesting.input_file_missing
        nesting.queued
        nesting.preparing
      ]
    ).freeze

    TERMINAL_STATUS_KEYS = {
      "completed" => "nesting.completed",
      "partial" => "nesting.partial",
      "failed" => "nesting.failed"
    }.freeze

    def self.for(project)
      new(project).to_s
    end

    def self.time_limit_notice?(project)
      new(project).time_limit_notice?
    end

    def initialize(project)
      @project = project
      @stored = project.progress_message.to_s
    end

    def to_s
      return "" if @stored.blank? && !terminal_status?

      key = terminal_message_key
      return I18n.t(key) if key.present?
      return I18n.t(@stored) if message_key?(@stored)

      resolve_legacy(@stored) || @stored
    end

    def time_limit_notice?
      return false unless @project.partial?

      message_key?("nesting.time_limit_notice") || matches_any_locale?("nesting.time_limit_notice", @stored)
    end

    private

    def terminal_status?
      TERMINAL_STATUS_KEYS.key?(@project.status)
    end

    def terminal_message_key
      return nil unless terminal_status?

      if @project.partial? && time_limit_notice?
        return "nesting.time_limit_notice"
      end

      if @project.failed? && cancelled_message?
        return "nesting.cancelled"
      end

      if @project.failed? && input_file_missing_message?
        return "nesting.input_file_missing"
      end

      TERMINAL_STATUS_KEYS[@project.status]
    end

    def cancelled_message?
      stored_matches_message_key?("nesting.cancelled")
    end

    def input_file_missing_message?
      stored_matches_message_key?("nesting.input_file_missing")
    end

    def stored_matches_message_key?(key)
      @stored == key || matches_any_locale?(key, @stored)
    end

    def message_key?(value)
      value.to_s.start_with?("nesting.")
    end

    def resolve_legacy(text)
      key = KNOWN_KEYS.find { |candidate| matches_any_locale?(candidate, text) }
      I18n.t(key) if key
    end

    def matches_any_locale?(key, text)
      return false if text.blank?

      I18n.available_locales.any? do |locale|
        I18n.t(key, locale: locale, default: "") == text
      end
    end
  end
end
