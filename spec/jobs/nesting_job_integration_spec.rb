# frozen_string_literal: true

require "rails_helper"

RSpec.describe NestingJob, "integration with nest.py", type: :job do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "#perform [REQ-FIT-NEST-003]" do
    it "marks partial and records oversized orphans when the piece does not fit the sheet" do
      project = Project.create!(
        title: "Oversized integration",
        ephemeral: true,
        sheet_stocks_attributes: {
          "0" => { width_mm: 50, height_mm: 50, quantity: 1, sort_order: 0 }
        }
      )
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      project.project_layers.create!(layer_name: "PIECES", included: true)
      nesting_run = project.nesting_runs.create!(status: "processing", params_snapshot: {})

      described_class.perform_now(nesting_run.id)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("partial")
      expect(nesting_run.report_json["status"]).to eq("partial")
      expect(nesting_run.report_json["orphans"]).not_to be_empty
      expect(nesting_run.report_json["orphans"].first["reason"]).to eq("oversized_for_sheet")
      expect(project.status).to eq("partial")
      expect(project.nested_dxf).to be_attached
    end

    it "marks completed when the piece fits the sheet via the real CLI" do
      project = Project.create!(
        title: "Fits integration",
        ephemeral: true,
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      )
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      project.project_layers.create!(layer_name: "PIECES", included: true)
      nesting_run = project.nesting_runs.create!(status: "processing", params_snapshot: {})

      described_class.perform_now(nesting_run.id)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("completed")
      expect(nesting_run.report_json["orphans"]).to eq([])
      expect(project.status).to eq("completed")
      expect(project.nested_dxf).to be_attached
    end
  end
end
