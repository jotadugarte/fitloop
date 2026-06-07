# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::JobRunner do
  let(:project) do
    Project.create!(title: "Job runner bench",
            nesting_time_limit_sec: 600,
      estimated_finished_at: 1.second.ago,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end
  let(:nesting_run) { project.nesting_runs.create!(status: "processing", params_snapshot: {}) }

  describe ".call [REQ-FIT-JOB-001]" do
    it "raises CancelledError when cancel is requested during CLI execution [REQ-FIT-JOB-001]" do
      stub_const("Nesting::JobRunner::CANCEL_CACHE_TTL_SEC", 0)
      allow(Nesting::CliRunner).to receive(:call) do |cancel_check:, **|
        nesting_run.update!(cancel_requested_at: Time.current)
        cancel_check.call
      end

      described_class.call(nesting_run: nesting_run)

      expect(nesting_run.reload.status).to eq("failed")
    end

    it "cancels when cancel_requested_at is set before the CLI runs [REQ-FIT-JOB-001]" do
      nesting_run.update!(cancel_requested_at: Time.current)

      described_class.call(nesting_run: nesting_run)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("failed")
      expect(project.status).to eq("failed")
      expect(project.progress_message).to eq("nesting.cancelled")
    end

    it "applies cancel after a successful CLI when cancel is observed at the end [REQ-FIT-JOB-001]" do
      stub_const("Nesting::JobRunner::CANCEL_CACHE_TTL_SEC", 0)
      allow(Nesting::CliRunner).to receive(:call) { nesting_run.update!(cancel_requested_at: Time.current) }
      allow(Nesting::ApplyCancel).to receive(:call)

      described_class.call(nesting_run: nesting_run)

      expect(Nesting::ApplyCancel).to have_received(:call).with(hash_including(nesting_run: nesting_run))
    end

    it "[REQ-FIT-SPLIT-001] invalidates draft split proposals when nesting is cancelled" do
      resolution = OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :system_split
      )
      draft = resolution.split_proposals.create!(
        status: :draft,
        version: 1,
        feasible: true,
        child_piece_geometries: [ { "label" => "a", "rings" => [] } ],
        cut_segments: [],
        labels: [ "a" ]
      )

      nesting_run.update!(cancel_requested_at: Time.current)
      described_class.call(nesting_run: nesting_run)

      expect(SplitProposal.exists?(draft.id)).to be(false)
    end

    it "marks partial and shows time limit notice when the time limit is exceeded [REQ-FIT-JOB-001]" do
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output")
      FileUtils.mkdir_p(work_dir)
      File.write(work_dir.join("nested.dxf"), "PARTIAL NESTED")
      File.write(work_dir.join("placements.json"), { sheets: [] }.to_json)
      File.write(work_dir.join("report.json"), "not-json")
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)

      described_class.call(nesting_run: nesting_run)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("partial")
      expect(project.status).to eq("partial")
      expect(project.progress_message).to eq("nesting.time_limit_notice")
      expect(project.nested_dxf).to be_attached
      expect(project.placements_json).to be_attached
    end

    it "handles CLI cancellation raised as CancelledError [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call).and_raise(Nesting::CancelledError)

      described_class.call(nesting_run: nesting_run)

      expect(nesting_run.reload.status).to eq("processing")
    end

    it "applies cancel when cancel_requested_at is set and CLI raises CancelledError [REQ-FIT-JOB-001]" do
      nesting_run.update!(cancel_requested_at: Time.current)
      allow(Nesting::CliRunner).to receive(:call).and_raise(Nesting::CancelledError)

      described_class.call(nesting_run: nesting_run)

      expect(nesting_run.reload.status).to eq("failed")
      expect(project.reload.progress_message).to eq("nesting.cancelled")
    end

    it "marks failed and broadcasts when the CLI raises [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call).and_raise(StandardError, "nest exploded")
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      described_class.call(nesting_run: nesting_run)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("failed")
      expect(project.status).to eq("failed")
      expect(project.progress_message).to eq("nesting.failed")
      expect(Nesting::ProgressBroadcaster).to have_received(:call).with(
        hash_including(project: project, eta_overrun: false, time_limit_notice: false)
      )
    end

    it "broadcasts eta overrun when past estimated_finished_at [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call)
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      described_class.call(nesting_run: nesting_run)

      expect(Nesting::ProgressBroadcaster).to have_received(:call).with(
        hash_including(project: project, eta_overrun: true)
      ).at_least(:once)
    end

    it "does not reload nesting_run on each cancel poll during CLI execution [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call) do |cancel_check:, **|
        20.times { cancel_check.call }
      end

      expect(nesting_run).not_to receive(:reload)

      described_class.call(nesting_run: nesting_run)
    end

    it "uses pre-CLI phase label before invoking the CLI [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call)
      project.update!(progress_percent: 8, progress_message: "nesting.phase.preparing")
      runner = described_class.new(nesting_run: nesting_run)
      allow(runner).to receive(:update_progress!).and_call_original

      runner.call

      expect(runner).to have_received(:update_progress!).with(
        percent: 12,
        message: I18n.t("nesting.phase.starting")
      )
    end

    it "does not leave stale 5%/15% pre-CLI progress ticks [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call)
      runner = described_class.new(nesting_run: nesting_run)
      allow(runner).to receive(:update_progress!).and_call_original

      runner.call

      expect(runner).to have_received(:update_progress!).with(
        percent: 12,
        message: I18n.t("nesting.phase.starting")
      )
      expect(runner).not_to have_received(:update_progress!).with(
        hash_including(message: I18n.t("nesting.preparing"))
      )
      expect(runner).not_to have_received(:update_progress!).with(
        hash_including(message: I18n.t("nesting.running"))
      )
    end

    it "throttles cancel_requested_at DB reads during CLI polling [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call) do |cancel_check:, **|
        20.times { cancel_check.call }
      end

      expect(NestingRun).to receive(:where).with(id: nesting_run.id).at_most(:once).and_call_original

      described_class.call(nesting_run: nesting_run)
    end

    it "completes successfully and emits terminal progress for completed runs [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call)
      project.update!(status: :completed)
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      described_class.call(nesting_run: nesting_run)

      expect(project.reload.progress_message).to eq("nesting.completed")
    end

    it "returns early after success when cancellation is requested post-run [REQ-FIT-JOB-001]" do
      allow(Nesting::CliRunner).to receive(:call)
      allow(Nesting::ProgressBroadcaster).to receive(:call)
      runner = described_class.new(nesting_run: nesting_run)
      allow(runner).to receive(:handle_cancelled!).and_return(false, true)

      runner.call

      expect(Nesting::ProgressBroadcaster).not_to have_received(:call).with(
        hash_including(percent: 100)
      )
    end

    it "does not attach outputs for non-terminal timeout statuses [REQ-FIT-JOB-001]" do
      runner = described_class.new(nesting_run: nesting_run)

      expect do
        runner.send(:attach_outputs_if_present!, Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s), "failed")
      end.not_to change { project.reload.nested_dxf.attached? }
    end

    it "handles failures when error backtrace is nil [REQ-FIT-JOB-001]" do
      error = StandardError.new("no trace")
      allow(error).to receive(:backtrace).and_return(nil)
      allow(Nesting::CliRunner).to receive(:call).and_raise(error)

      expect { described_class.call(nesting_run: nesting_run) }.not_to raise_error
      expect(nesting_run.reload.status).to eq("failed")
    end
  end
end
