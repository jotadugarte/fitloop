# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::SplitPlannerRunner, "[REQ-FIT-SPLIT-001]" do
  let(:project) { create_project_for_spec!(title: "Split runner") }

  it "[REQ-FIT-SPLIT-001] passes orphan rings as plan_pieces in config.json" do
    project.placements_json.attach(
      io: StringIO.new(
        {
          sheets: [],
          orphans: [
            {
              piece_index: 11,
              piece_key: "11",
              reason: "oversized_for_sheet",
              width_mm: 480.0,
              height_mm: 480.0,
              offset_x_mm: 0.0,
              offset_y_mm: 0.0,
              rings: [ [ [ 0.0, 0.0 ], [ 480.0, 0.0 ], [ 480.0, 480.0 ], [ 0.0, 480.0 ] ] ]
            }
          ]
        }.to_json
      ),
      filename: "placements.json",
      content_type: "application/json"
    )
    resolution = OrphanResolution.create!(
      project: project,
      piece_key: "11",
      reason: "oversized_for_sheet",
      resolution_state: :system_split
    )
    captured_config = nil
    invoke = lambda do |work_dir, _config_path|
      captured_config = JSON.parse(File.read(work_dir.join("config.json")))
      FileUtils.mkdir_p(work_dir.join("output"))
      File.write(
        work_dir.join("output/split_preview.json"),
        {
          proposals: [
            {
              piece_key: "11",
              feasible: true,
              reason: nil,
              children: [],
              cut_segments: []
            }
          ],
          warnings: []
        }.to_json
      )
      0
    end

    described_class.call(orphan_resolution: resolution, invoke: invoke)

    plan_piece = captured_config.fetch("plan_pieces").sole
    expect(plan_piece.fetch("piece_key")).to eq("11")
    expect(plan_piece.fetch("rings").first.first).to eq([ 0.0, 0.0 ])
    expect(plan_piece.fetch("rings").first[2]).to eq([ 480.0, 480.0 ])
  end
end
