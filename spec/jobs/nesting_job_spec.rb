# frozen_string_literal: true

require "rails_helper"

RSpec.describe NestingJob, type: :job do
  let(:project) do
    Project.create!(
      title: "CLI bridge bench",
        ephemeral: true,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }
  let(:nesting_run) { project.nesting_runs.create!(status: "processing", params_snapshot: {}) }

  before do
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)
  end

  describe "#perform [REQ-FIT-CLI-001]" do
    it "writes config.json, invokes nest.py, and attaches nested.dxf" do
      described_class.perform_now(nesting_run.id)

      nesting_run.reload
      project.reload

      snapshot = nesting_run.params_snapshot
      expect(snapshot).to include(
        "project_id" => project.id.to_s,
        "included_layers" => [ "PIECES" ]
      )
      expect(snapshot.fetch("input_dxf_paths")).to all(be_a(String))
      expect(snapshot.fetch("sheet_stocks").first).to include("width_mm" => 1000.0)
      expect(nesting_run.status).to eq("completed")
      expect(nesting_run.report_json).to include("status" => "completed")
      expect(nesting_run.finished_at).to be_present
      expect(project.status).to eq("completed")
      expect(project.nested_dxf).to be_attached
    end

    it "no-ops when the nesting run no longer exists" do
      expect do
        described_class.perform_now(-1)
      end.not_to raise_error
    end

    it "marks the run failed when the project was removed" do
      orphan_run = nesting_run
      allow(NestingRun).to receive(:find_by).with(id: nesting_run.id).and_return(orphan_run)
      allow(orphan_run).to receive(:project).and_return(nil)

      described_class.perform_now(nesting_run.id)

      orphan_run.reload
      expect(orphan_run.status).to eq("failed")
      expect(orphan_run.report_json).to include("warnings" => [ "project_missing" ])
    end

    it "fails the run when JobRunner raises" do
      allow(Nesting::JobRunner).to receive(:call).and_raise(StandardError, "cli boom")

      described_class.perform_now(nesting_run.id)

      nesting_run.reload
      expect(nesting_run.status).to eq("failed")
    end
  end

  describe "failure and telemetry branches [REQ-FIT-ANALYTICS-001]" do
    it "skips FailRun when the run is no longer processing after an error" do
      allow(Nesting::JobRunner).to receive(:call).and_raise(StandardError, "late failure")
      completed_run = nesting_run
      allow(NestingRun).to receive(:find_by).with(id: nesting_run.id).and_return(completed_run)
      allow(completed_run).to receive(:status).and_return("completed")

      expect(Nesting::FailRun).not_to receive(:call)

      described_class.perform_now(nesting_run.id)
    end

    it "computes duration from started_at when finished_at is present" do
      nesting_run.update!(started_at: 2.seconds.ago, finished_at: Time.current, status: "completed")
      job = described_class.new

      expect(job.send(:compute_duration_ms, nesting_run)).to be > 0
    end

    it "returns an empty orphan reason map when report has no orphans" do
      nesting_run.update!(report_json: { "status" => "completed" })
      job = described_class.new

      expect(job.send(:parse_orphans_by_reason, nesting_run)).to eq({})
    end
  end

  describe "telemetry helpers [REQ-FIT-ANALYTICS-001]" do
    it "returns zero sheet and piece counts when placements.json cannot be parsed" do
      output_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output")
      FileUtils.mkdir_p(output_dir)
      File.write(output_dir.join("placements.json"), "not-json")
      job = described_class.new

      expect(job.send(:parse_sheets_used, nesting_run)).to eq(0)
      expect(job.send(:parse_pieces_count, nesting_run)).to eq(0)
    ensure
      FileUtils.rm_rf(Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s))
    end

    it "returns correct sheet and piece counts from placements.json when present on disk [REQ-FIT-ANALYTICS-001]" do
      output_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output")
      FileUtils.mkdir_p(output_dir)
      File.write(
        output_dir.join("placements.json"),
        {
          "sheets" => [
            { "pieces" => [ { "label" => "1" }, { "label" => "2" } ] },
            { "pieces" => [ { "label" => "3" } ] }
          ]
        }.to_json
      )
      job = described_class.new

      expect(job.send(:parse_sheets_used, nesting_run)).to eq(2)
      expect(job.send(:parse_pieces_count, nesting_run)).to eq(3)
    ensure
      FileUtils.rm_rf(Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s))
    end

    it "returns sheets and pieces from report_json when present [REQ-FIT-ANALYTICS-001]" do
      nesting_run.update!(
        report_json: {
          "sheets_used" => 5,
          "pieces_count" => 10
        }
      )
      job = described_class.new

      expect(job.send(:parse_sheets_used, nesting_run)).to eq(5)
      expect(job.send(:parse_pieces_count, nesting_run)).to eq(10)
    end
  end
end
