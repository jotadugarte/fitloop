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
    it "maps non-zero CLI exit to failed status" do
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

    it "raises CancelledError when cancel_check is true during invoke polling" do
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
  end
end
