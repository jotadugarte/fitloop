# frozen_string_literal: true

module Nesting
  # Aligns a processing nesting run when its Solid Queue job already failed.
  class ReconcileFailedJob
    ABANDON_AFTER = 90.seconds

    def self.call(nesting_run:)
      new(nesting_run: nesting_run).call
    end

    def initialize(nesting_run:)
      @nesting_run = nesting_run
    end

    def call
      return false unless @nesting_run.status == "processing"

      if solid_queue_job_failed?
        FailRun.call(nesting_run: @nesting_run, message: I18n.t("nesting.failed"))
        return true
      end

      return false unless abandoned_without_output?

      FailRun.call(nesting_run: @nesting_run, message: I18n.t("nesting.failed"))
    end

    private

    def solid_queue_job_failed?
      return false unless solid_queue_tables?

      SolidQueue::FailedExecution
        .joins(:job)
        .where(solid_queue_jobs: { class_name: "NestingJob" })
        .where("solid_queue_jobs.arguments LIKE ?", "%\"arguments\": [#{@nesting_run.id}]%")
        .exists?
    end

    def solid_queue_tables?
      connection = ActiveRecord::Base.connection
      connection.data_source_exists?("solid_queue_jobs") &&
        connection.data_source_exists?("solid_queue_failed_executions")
    end

    def abandoned_without_output?
      anchor = @nesting_run.started_at || @nesting_run.created_at
      return false if anchor > ABANDON_AFTER.ago

      work_dir = Pathname(Rails.root.join("tmp/nesting_runs", @nesting_run.id.to_s))
      return false if work_dir.join("output", "report.json").file?

      !work_dir.directory?
    end
  end
end
