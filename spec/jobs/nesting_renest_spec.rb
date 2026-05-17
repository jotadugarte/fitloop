# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Re-nest job output", type: :job do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  it "[REQ-FIT-NEST-004] replaces the downloadable nested DXF on a subsequent run" do
    project = Project.create!(
      title: "Replace nested output",
      pin: "667799",
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
    project.nested_dxf.attach(
      io: StringIO.new("OLD NESTED DXF"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    first_run = project.nesting_runs.create!(status: "completed", params_snapshot: {})
    second_run = project.nesting_runs.create!(status: "processing", params_snapshot: {})

    NestingJob.perform_now(second_run.id)

    project.reload
    expect(project.nesting_runs.count).to eq(2)
    expect(first_run.reload.status).to eq("completed")
    expect(project.nested_dxf).to be_attached
    expect(project.nested_dxf.download).not_to include("OLD NESTED DXF")
    expect(project.placements_json).to be_attached
  end
end
