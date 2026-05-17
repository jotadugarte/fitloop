# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-003] Surfaces orphan pieces from the latest nesting report.
  class OrphansPresenter
    def self.for(project)
      new(project: project)
    end

    def initialize(project:)
      @project = project
    end

    def any?
      entries.any?
    end

    def entries
      @entries ||= Array(latest_report&.fetch("orphans", nil))
    end

    private

    def latest_report
      @project.nesting_runs.order(created_at: :desc).pick(:report_json)
    end
  end
end
