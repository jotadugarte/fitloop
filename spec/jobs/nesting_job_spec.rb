# frozen_string_literal: true

require "rails_helper"

RSpec.describe NestingJob, type: :job do
  let(:project) do
    Project.create!(
      title: "CLI bridge bench",
      pin: "334455",
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
    it "writes config.json, invokes the mock CLI, and attaches nested.dxf" do
      described_class.perform_now(nesting_run.id)

      nesting_run.reload
      project.reload

      snapshot = nesting_run.params_snapshot
      expect(snapshot).to include(
        "project_id" => project.id.to_s,
        "included_layers" => ["PIECES"]
      )
      expect(snapshot.fetch("input_dxf_paths")).to all(be_a(String))
      expect(snapshot.fetch("sheet_stocks").first).to include("width_mm" => 1000.0)
      expect(nesting_run.status).to eq("completed")
      expect(nesting_run.report_json).to include("status" => "completed")
      expect(nesting_run.finished_at).to be_present
      expect(project.status).to eq("completed")
      expect(project.nested_dxf).to be_attached
    end
  end
end
