# frozen_string_literal: true

module Nesting
  # [REQ-FIT-JOB-001] Human-readable time remaining until estimated_finished_at.
  class TimeRemainingMessage
    def self.for(project, now: Time.current)
      return nil unless project.processing?

      eta = project.estimated_finished_at
      return nil if eta.blank?
      return nil if now >= eta

      minutes = ((eta - now) / 60.0).ceil
      minutes = 1 if minutes < 1
      I18n.t("nesting.time_remaining", count: minutes)
    end
  end
end
