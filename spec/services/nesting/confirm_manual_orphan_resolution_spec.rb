# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ConfirmManualOrphanResolution do
  let(:project) { create_project_for_spec!(title: "Manual confirm") }

  def attach_orphan!(rings:)
    project.nesting_runs.create!(
      status: "partial",
      report_json: { "orphans" => [ { "piece_index" => 0, "reason" => "oversized_for_sheet" } ] },
      finished_at: Time.current
    )
    project.placements_json.attach(
      io: StringIO.new(
        {
          sheets: [],
          orphans: [
            {
              piece_index: 0,
              reason: "oversized_for_sheet",
              width_mm: 100.0,
              height_mm: 50.0,
              offset_x_mm: 0.0,
              offset_y_mm: 0.0,
              rings: rings
            }
          ]
        }.to_json
      ),
      filename: "placements.json",
      content_type: "application/json"
    )
  end

  it "[REQ-FIT-SPLIT-001] resolves when mother geometry is gone" do
    rings = [ [ [ 0.0, 0.0 ], [ 500.0, 0.0 ], [ 500.0, 500.0 ], [ 0.0, 500.0 ] ] ]
    attach_orphan!(rings: rings)
    resolution = OrphanResolution.create!(
      project: project,
      piece_key: "0",
      reason: "oversized_for_sheet",
      resolution_state: :manual
    )
    sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)

    result = described_class.call(project: project, orphan_resolution: resolution)

    expect(result.ok?).to be(true)
    expect(resolution.reload.resolution_state).to eq("resolved")
  end
end
