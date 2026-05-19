# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::JobRunner do
  let(:project) do
    Project.create!(
      title: "Job runner bench",
      pin: "667788",
      nesting_time_limit_sec: 600,
      estimated_finished_at: 1.second.ago,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end
  let(:nesting_run) { project.nesting_runs.create!(status: "processing", params_snapshot: {}) }

  describe ".call [REQ-FIT-JOB-001]" do
    it "cancels when cancel_requested_at is set before the CLI runs" do
      nesting_run.update!(cancel_requested_at: Time.current)

      described_class.call(nesting_run: nesting_run)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("failed")
      expect(project.status).to eq("failed")
      expect(project.progress_message).to eq(I18n.t("nesting.cancelled"))
    end

    it "marks partial and shows time limit notice when the time limit is exceeded" do
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      described_class.call(nesting_run: nesting_run)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("partial")
      expect(project.status).to eq("partial")
      expect(project.progress_message).to eq(I18n.t("nesting.time_limit_notice"))
    end

    it "marks failed and broadcasts when the CLI raises" do
      allow(Nesting::CliRunner).to receive(:call).and_raise(StandardError, "nest exploded")
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      described_class.call(nesting_run: nesting_run)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("failed")
      expect(project.status).to eq("failed")
      expect(project.progress_message).to eq(I18n.t("nesting.failed"))
      expect(Nesting::ProgressBroadcaster).to have_received(:call).with(
        hash_including(project: project, eta_overrun: false, time_limit_notice: false)
      )
    end

    it "broadcasts eta overrun when past estimated_finished_at" do
      allow(Nesting::CliRunner).to receive(:call)
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      described_class.call(nesting_run: nesting_run)

      expect(Nesting::ProgressBroadcaster).to have_received(:call).with(
        hash_including(project: project, eta_overrun: true)
      ).at_least(:once)
    end

    it "does not reload nesting_run on each cancel poll during CLI execution" do
      allow(Nesting::CliRunner).to receive(:call) do |cancel_check:, **|
        20.times { cancel_check.call }
      end

      expect(nesting_run).not_to receive(:reload)

      described_class.call(nesting_run: nesting_run)
    end

    it "throttles cancel_requested_at DB reads during CLI polling" do
      allow(Nesting::CliRunner).to receive(:call) do |cancel_check:, **|
        20.times { cancel_check.call }
      end

      expect(NestingRun).to receive(:where).with(id: nesting_run.id).at_most(:once).and_call_original

      described_class.call(nesting_run: nesting_run)
    end
  end
end
