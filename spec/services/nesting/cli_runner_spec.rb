# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::CliRunner do
  let(:project) do
    Project.create!(
      title: "CLI runner bench",
        ephemeral: true,
      sheet_stocks_attributes: {
        "0" => { width_mm: 500, height_mm: 500, quantity: nil, sort_order: 0 }
      }
    )
  end
  let(:nesting_run) { project.nesting_runs.create!(status: "processing", params_snapshot: {}) }

  describe ".call [REQ-FIT-CLI-001]" do
    it "maps non-zero CLI exit to failed status [REQ-FIT-CLI-001]" do
      mock_invoke = ->(_work_dir, _config_path) { 1 }

      described_class.call(nesting_run: nesting_run, invoke: mock_invoke)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("failed")
      expect(project.status).to eq("failed")
    end

    it "updates project progress from progress.json during the poll loop [REQ-FIT-JOB-001]" do
      project.update!(
        status: :processing,
        progress_percent: 15,
        progress_message: "Starting"
      )
      nesting_run.update!(started_at: 1.minute.ago)
      I18n.backend.store_translations(
        :en,
        nesting: { phase: { fill: "Placing pieces on sheets" } }
      )

      slow_invoke = lambda do |work_dir, _config_path|
        output_dir = work_dir.join("output")
        FileUtils.mkdir_p(output_dir)
        File.write(
          output_dir.join("progress.json"),
          {
            version: 1,
            phase_id: "fill",
            percent: 55,
            pieces_total: 10,
            pieces_placed: 5
          }.to_json
        )
        sleep 0.35
        0
      end

      described_class.call(nesting_run: nesting_run, invoke: slow_invoke)

      project.reload
      expect(project.progress_percent).to eq(55)
      expect(project.progress_message).to eq("nesting.phase.fill")
    end

    it "kills the Open3 child process when cancellation is requested during CLI execution [REQ-FIT-CLI-001]" do
      wait_thr = double("Open3 wait thread", pid: 99_999)
      checks = 0
      allow(wait_thr).to receive(:join).with(0.2).and_return(false, true)
      allow(wait_thr).to receive(:value).and_return(instance_double(Process::Status, exitstatus: 0))
      allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)
      allow(Process).to receive(:kill)

      expect do
        described_class.call(
          nesting_run: nesting_run,
          cancel_check: lambda do
            checks += 1
            checks >= 3
          end
        )
      end.to raise_error(Nesting::CancelledError)

      expect(Process).to have_received(:kill).with("TERM", 99_999)
    end

    it "raises CancelledError when cancel_check is true during invoke polling [REQ-FIT-CLI-001]" do
      checks = 0
      cancel_check = lambda do
        checks += 1
        checks >= 2
      end

      slow_invoke = lambda do |_work_dir, _config_path|
        sleep 1.0
        0
      end

      expect do
        described_class.call(
          nesting_run: nesting_run,
          invoke: slow_invoke,
          cancel_check: cancel_check
        )
      end.to raise_error(Nesting::CancelledError)
    end

    it "runs invoke without a cancel_check callback [REQ-FIT-CLI-001]" do
      described_class.call(nesting_run: nesting_run, invoke: ->(_work_dir, _config_path) { 0 })

      expect(nesting_run.reload.status).to eq("failed")
    end

    it "skips nested output attachment when nested.dxf is absent [REQ-FIT-CLI-001]" do
      described_class.call(nesting_run: nesting_run, invoke: ->(_work_dir, _config_path) { 0 })

      expect(project.reload.nested_dxf).not_to be_attached
    end

    it "does not finalize runs that already left processing [REQ-FIT-CLI-001]" do
      nesting_run.update!(status: "completed", finished_at: Time.current)

      described_class.call(nesting_run: nesting_run, invoke: ->(_work_dir, _config_path) { 0 })

      expect(nesting_run.reload.status).to eq("completed")
    end
  end

  describe ".finalize_from_work_dir! [REQ-FIT-CLI-001]" do
    it "returns false when the work directory is missing [REQ-FIT-CLI-001]" do
      expect(described_class.finalize_from_work_dir!(nesting_run: nesting_run)).to be(false)
    end

    it "returns false when report.json is empty [REQ-FIT-CLI-001]" do
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s)
      FileUtils.mkdir_p(work_dir.join("output"))

      expect(described_class.finalize_from_work_dir!(nesting_run: nesting_run)).to be(false)
    ensure
      FileUtils.rm_rf(work_dir)
    end
  end
end
