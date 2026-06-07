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

  it "[REQ-FIT-SPLIT-001] materializes attached DXF inputs before invoking the CLI" do
    sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.placements_json.attach(
      io: StringIO.new({ sheets: [], orphans: [] }.to_json),
      filename: "placements.json",
      content_type: "application/json"
    )
    resolution = OrphanResolution.create!(
      project: project,
      piece_key: "0",
      reason: "oversized_for_sheet",
      resolution_state: :system_split
    )
    work_dirs = []
    invoke = lambda do |work_dir, _config_path|
      work_dirs << work_dir
      FileUtils.mkdir_p(work_dir.join("output"))
      File.write(
        work_dir.join("output/split_preview.json"),
        { proposals: [ { piece_key: "0", feasible: false, reason: "split_not_feasible" } ] }.to_json
      )
      0
    end

    described_class.call(orphan_resolution: resolution, invoke: invoke)

    expect(work_dirs.first.join("inputs/piece.dxf")).to exist
  end

  it "[REQ-FIT-SPLIT-001] omits plan_pieces when orphan geometry is not exportable" do
    project.placements_json.attach(
      io: StringIO.new(
        {
          sheets: [],
          orphans: [
            {
              piece_index: 3,
              piece_key: "3",
              reason: "oversized_for_sheet",
              width_mm: 10.0,
              height_mm: 10.0,
              offset_x_mm: 0.0,
              offset_y_mm: 0.0,
              rings: []
            }
          ]
        }.to_json
      ),
      filename: "placements.json",
      content_type: "application/json"
    )
    resolution = OrphanResolution.create!(
      project: project,
      piece_key: "3",
      reason: "oversized_for_sheet",
      resolution_state: :system_split
    )
    captured_config = nil
    invoke = lambda do |work_dir, _config_path|
      captured_config = JSON.parse(File.read(work_dir.join("config.json")))
      FileUtils.mkdir_p(work_dir.join("output"))
      File.write(
        work_dir.join("output/split_preview.json"),
        { proposals: [ { piece_key: "3", feasible: false, reason: "split_not_feasible" } ] }.to_json
      )
      0
    end

    described_class.call(orphan_resolution: resolution, invoke: invoke)

    expect(captured_config).not_to have_key("plan_pieces")
  end

  it "[REQ-FIT-SPLIT-001] runs the Python CLI when no invoke stub is provided" do
    project.placements_json.attach(
      io: StringIO.new({ sheets: [], orphans: [] }.to_json),
      filename: "placements.json",
      content_type: "application/json"
    )
    resolution = OrphanResolution.create!(
      project: project,
      piece_key: "0",
      reason: "oversized_for_sheet",
      resolution_state: :system_split
    )
    wait_thr = instance_double(Process::Waiter, value: instance_double(Process::Status, exitstatus: 0))
    allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)
    allow(File).to receive(:write)
    runner = described_class.new(orphan_resolution: resolution)
    allow(runner).to receive(:prepare_work_dir).and_return(Pathname("/tmp/split-test"))
    allow(runner).to receive(:materialize_input_dxfs!).and_return([])
    allow(runner).to receive(:load_proposal!).and_return({ "piece_key" => "0" })

    expect(runner.send(:run_cli!, Pathname("/tmp/split-test"))).to eq(0)
  end

  it "[REQ-FIT-SPLIT-001] raises when the Python CLI exits non-zero" do
    wait_thr = instance_double(Process::Waiter, value: instance_double(Process::Status, exitstatus: 2))
    allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)
    runner = described_class.new(
      orphan_resolution: OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :system_split
      )
    )

    expect { runner.send(:run_cli!, Pathname("/tmp/split-fail")) }
      .to raise_error(/split planner CLI failed with exit 2/)
  end

  it "[REQ-FIT-SPLIT-001] raises when split_preview.json is missing or incomplete" do
    resolution = OrphanResolution.create!(
      project: project,
      piece_key: "9",
      reason: "oversized_for_sheet",
      resolution_state: :system_split
    )
    runner = described_class.new(orphan_resolution: resolution)
    work_dir = Pathname(Dir.mktmpdir("split-preview-missing"))

    expect { runner.send(:load_proposal!, work_dir) }.to raise_error("split_preview.json missing")

    FileUtils.mkdir_p(work_dir.join("output"))
    File.write(work_dir.join("output/split_preview.json"), { proposals: [] }.to_json)

    expect { runner.send(:load_proposal!, work_dir) }
      .to raise_error(/split preview missing proposal/)
  ensure
    FileUtils.rm_rf(work_dir) if work_dir
  end
end
