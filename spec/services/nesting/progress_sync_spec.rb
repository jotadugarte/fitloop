# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProgressSync do
  let(:project) do
    create_project_for_spec!(
      title: "Progress sync bench",
      status: :processing,
      progress_percent: 15,
      progress_message: "Starting",
      nesting_time_limit_sec: 600,
      estimated_finished_at: 10.minutes.from_now
    )
  end
  let(:nesting_run) do
    project.nesting_runs.create!(
      status: "processing",
      started_at: 2.minutes.ago,
      params_snapshot: {}
    )
  end

  before do
    I18n.backend.store_translations(
      :en,
      nesting: { phase: { fill: "Placing pieces on sheets" } }
    )
  end

  def snapshot(percent:, pieces_total: nil, pieces_placed: nil)
    Nesting::ProgressSnapshot.from_hash(
      {
        "version" => 1,
        "phase_id" => "fill",
        "percent" => percent,
        "pieces_total" => pieces_total,
        "pieces_placed" => pieces_placed
      }.compact,
      last_percent: 0
    )
  end

  describe ".call [REQ-FIT-JOB-001]" do
    it "updates project progress from snapshot and broadcasts when changed" do
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      changed = described_class.call(
        project: project,
        snapshot: snapshot(percent: 42, pieces_total: 10, pieces_placed: 5),
        nesting_run: nesting_run
      )

      project.reload
      expect(changed).to be(true)
      expect(project.progress_percent).to eq(42)
      expect(project.progress_message).to eq("Placing pieces on sheets")
      expect(Nesting::ProgressBroadcaster).to have_received(:call).with(
        project: project,
        eta_overrun: false,
        time_limit_notice: false
      )
    end

    it "computes estimated_finished_at from pieces ratio and elapsed time" do
      started_at = 100.seconds.ago
      nesting_run.update!(started_at: started_at)

      described_class.call(
        project: project,
        snapshot: snapshot(percent: 50, pieces_total: 100, pieces_placed: 50),
        nesting_run: nesting_run,
        broadcast: false
      )

      project.reload
      expect(project.estimated_finished_at).to be_within(2.seconds).of(started_at + 200.seconds)
    end

    it "does not raise project percent above snapshot percent" do
      project.update!(progress_percent: 60)

      described_class.call(
        project: project,
        snapshot: snapshot(percent: 42),
        nesting_run: nesting_run,
        broadcast: false
      )

      expect(project.reload.progress_percent).to eq(42)
    end

    it "skips update and broadcast when snapshot is nil" do
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      changed = described_class.call(project: project, snapshot: nil, nesting_run: nesting_run)

      expect(changed).to be(false)
      expect(Nesting::ProgressBroadcaster).not_to have_received(:call)
      expect(project.reload.progress_percent).to eq(15)
    end

    it "skips broadcast when progress fields are unchanged" do
      project.update!(
        progress_percent: 42,
        progress_message: I18n.t("nesting.phase.fill"),
        estimated_finished_at: Nesting::ProgressEta.estimate(
          started_at: nesting_run.started_at,
          time_limit_sec: project.nesting_time_limit_sec,
          pieces_total: nil,
          pieces_placed: nil
        )
      )
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      changed = described_class.call(
        project: project,
        snapshot: snapshot(percent: 42),
        nesting_run: nesting_run
      )

      expect(changed).to be(false)
      expect(Nesting::ProgressBroadcaster).not_to have_received(:call)
    end
  end
end
