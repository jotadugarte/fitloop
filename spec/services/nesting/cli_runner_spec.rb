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

      killed = false
      allow(Process).to receive(:kill) do |sig, pid|
        if pid == 99_999
          if sig == 0 || sig == "0"
            raise Errno::ESRCH if killed
          elsif sig.to_s == "TERM"
            killed = true
          end
        end
        0
      end

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

    it "kills the Open3 child process on Timeout::Error or other external interruption [REQ-FIT-CLI-001]" do
      wait_thr = double("Open3 wait thread", pid: 99_999)
      allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)

      killed = false
      allow(Process).to receive(:kill) do |sig, pid|
        if pid == 99_999
          if sig == 0 || sig == "0"
            raise Errno::ESRCH if killed
          elsif sig.to_s == "KILL"
            killed = true
          end
        end
        0
      end

      allow(described_class).to receive(:new).and_wrap_original do |original_method, *args, **kwargs|
        runner = original_method.call(*args, **kwargs)
        allow(runner).to receive(:wait_with_progress_poll).and_raise(Timeout::Error)
        allow(runner).to receive(:sleep)
        runner
      end

      expect do
        described_class.call(nesting_run: nesting_run)
      end.to raise_error(Timeout::Error)

      expect(Process).to have_received(:kill).with("TERM", 99_999)
      expect(Process).to have_received(:kill).with("KILL", 99_999)
    end

    it "kills with TERM and skips KILL fallback if the process exits [REQ-FIT-CLI-001]" do
      wait_thr = double("Open3 wait thread", pid: 99_998)
      allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)

      call_count = 0
      allow(Process).to receive(:kill) do |signal, pid|
        if pid == 99_998
          if signal == 0
            call_count += 1
            raise Errno::ESRCH if call_count > 1
          end
        end
        0
      end

      allow(described_class).to receive(:new).and_wrap_original do |original_method, *args, **kwargs|
        runner = original_method.call(*args, **kwargs)
        allow(runner).to receive(:wait_with_progress_poll).and_raise(Timeout::Error)
        allow(runner).to receive(:sleep)
        runner
      end

      expect do
        described_class.call(nesting_run: nesting_run)
      end.to raise_error(Timeout::Error)

      expect(Process).to have_received(:kill).with("TERM", 99_998)
      expect(Process).not_to have_received(:kill).with("KILL", 99_998)
    end

    it "raises Post-condition violation if process cannot be killed [REQ-FIT-CLI-001]" do
      wait_thr = double("Open3 wait thread", pid: 99_997)
      allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)

      # Process is always alive
      allow(Process).to receive(:kill).with(any_args).and_return(0)

      allow(described_class).to receive(:new).and_wrap_original do |original_method, *args, **kwargs|
        runner = original_method.call(*args, **kwargs)
        allow(runner).to receive(:wait_with_progress_poll).and_raise(Timeout::Error)
        allow(runner).to receive(:sleep)
        runner
      end

      expect do
        described_class.call(nesting_run: nesting_run)
      end.to raise_error(RuntimeError, /Post-condition violation: spawned process is still alive/)
    end

    it "rescues Errno::ESRCH if process dies right before sending TERM [REQ-FIT-CLI-001]" do
      wait_thr = double("Open3 wait thread", pid: 99_996)
      allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)

      first_check = true
      allow(Process).to receive(:kill) do |sig, pid|
        if pid == 99_996
          if sig == 0
            if first_check
              first_check = false
              0
            else
              raise Errno::ESRCH
            end
          elsif sig.to_s == "TERM"
            raise Errno::ESRCH
          end
        end
        0
      end

      allow(described_class).to receive(:new).and_wrap_original do |original_method, *args, **kwargs|
        runner = original_method.call(*args, **kwargs)
        allow(runner).to receive(:wait_with_progress_poll).and_raise(Timeout::Error)
        allow(runner).to receive(:sleep)
        runner
      end

      expect do
        described_class.call(nesting_run: nesting_run)
      end.to raise_error(Timeout::Error)
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

    it "handles nil sheets in placements.json when finalizing [REQ-FIT-CLI-001]" do
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s)
      FileUtils.mkdir_p(work_dir.join("output"))
      File.write(work_dir.join("output/report.json"), { "status" => "completed" }.to_json)
      File.write(work_dir.join("output/placements.json"), { "sheets" => nil }.to_json)

      expect(described_class.finalize_from_work_dir!(nesting_run: nesting_run)).to be(true)
      expect(nesting_run.reload.report_json["sheets_used"]).to eq(0)
      expect(nesting_run.reload.report_json["pieces_count"]).to eq(0)
    ensure
      FileUtils.rm_rf(work_dir)
    end

    it "handles nil pieces in placements.json when finalizing [REQ-FIT-CLI-001]" do
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s)
      FileUtils.mkdir_p(work_dir.join("output"))
      File.write(work_dir.join("output/report.json"), { "status" => "completed" }.to_json)
      File.write(work_dir.join("output/placements.json"), { "sheets" => [ { "pieces" => nil } ] }.to_json)

      expect(described_class.finalize_from_work_dir!(nesting_run: nesting_run)).to be(true)
      expect(nesting_run.reload.report_json["sheets_used"]).to eq(1)
      expect(nesting_run.reload.report_json["pieces_count"]).to eq(0)
    ensure
      FileUtils.rm_rf(work_dir)
    end

    it "handles missing sheets in placements.json when finalizing [REQ-FIT-CLI-001]" do
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s)
      FileUtils.mkdir_p(work_dir.join("output"))
      File.write(work_dir.join("output/report.json"), { "status" => "completed" }.to_json)
      File.write(work_dir.join("output/placements.json"), {}.to_json)

      expect(described_class.finalize_from_work_dir!(nesting_run: nesting_run)).to be(true)
      expect(nesting_run.reload.report_json["sheets_used"]).to eq(0)
      expect(nesting_run.reload.report_json["pieces_count"]).to eq(0)
    ensure
      FileUtils.rm_rf(work_dir)
    end
  end

  describe "#process_alive? [REQ-FIT-CLI-001]" do
    let(:runner) { described_class.new(nesting_run: nesting_run) }

    it "raises ArgumentError for invalid PIDs [REQ-FIT-CLI-001]" do
      expect { runner.send(:process_alive?, nil) }.to raise_error(ArgumentError, "Invalid PID")
      expect { runner.send(:process_alive?, -5) }.to raise_error(ArgumentError, "Invalid PID")
      expect { runner.send(:process_alive?, "abc") }.to raise_error(ArgumentError, "Invalid PID")
    end

    it "returns true if process is alive and we have permission [REQ-FIT-CLI-001]" do
      allow(Process).to receive(:kill).with(0, 12345).and_return(1)
      expect(runner.send(:process_alive?, 12345)).to be(true)
    end

    it "returns false if process does not exist [REQ-FIT-CLI-001]" do
      allow(Process).to receive(:kill).with(0, 12345).and_raise(Errno::ESRCH)
      expect(runner.send(:process_alive?, 12345)).to be(false)
    end

    it "returns true if process exists but we lack permission [REQ-FIT-CLI-001]" do
      allow(Process).to receive(:kill).with(0, 12345).and_raise(Errno::EPERM)
      expect(runner.send(:process_alive?, 12345)).to be(true)
    end
  end

  describe "#run_cli! [REQ-FIT-CLI-001]" do
    let(:runner) { described_class.new(nesting_run: nesting_run) }

    it "raises ArgumentError if work_dir is not a directory [REQ-FIT-CLI-001]" do
      expect do
        runner.send(:run_cli!, Rails.root.join("non_existent_directory"))
      end.to raise_error(ArgumentError, "work_dir must exist")
    end
  end
end
