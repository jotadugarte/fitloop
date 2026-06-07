# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::OrphansPresenter do
  let(:project) { create_project_for_spec!(title: "Orphans bench") }

  describe "Orphan value object [REQ-FIT-SPLIT-001]" do
    it "treats a nil split proposal as not feasible" do
      orphan = described_class::Orphan.new(split_proposal: nil)

      expect(orphan.split_not_feasible?).to be_nil
      expect(orphan.split_plan_failed?).to be_nil
    end
  end

  describe ".for [REQ-FIT-NEST-003]" do
    it "builds preview data from placements.json orphan geometry" do
      project.nesting_runs.create!(
        status: "partial",
        report_json: {
          "orphans" => [
            { "piece_index" => 0, "reason" => "oversized_for_sheet" },
            { "piece_index" => 4, "reason" => "oversized_for_sheet" }
          ]
        },
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
                width_mm: 800.0,
                height_mm: 400.0,
                offset_x_mm: 10.0,
                offset_y_mm: 20.0,
                rings: [ [ [ 10.0, 20.0 ], [ 810.0, 20.0 ], [ 810.0, 420.0 ], [ 10.0, 420.0 ] ] ]
              },
              {
                piece_index: 4,
                reason: "oversized_for_sheet",
                width_mm: 120.0,
                height_mm: 50.0,
                offset_x_mm: 0.0,
                offset_y_mm: 0.0,
                rings: [ [ [ 0.0, 0.0 ], [ 120.0, 0.0 ], [ 120.0, 50.0 ], [ 0.0, 50.0 ] ] ]
              }
            ]
          }.to_json
        ),
        filename: "placements.json",
        content_type: "application/json"
      )

      presenter = described_class.for(project)

      expect(presenter.any?).to be(true)
      expect(presenter.items.size).to eq(2)
      expect(presenter.items.first.display_number).to eq(1)
      expect(presenter.items.first.preview_available?).to be(true)
      expect(presenter.items.first.view_width).to eq(816.0)
      expect(presenter.entries).to contain_exactly(
        { "piece_index" => 0, "reason" => "oversized_for_sheet" },
        { "piece_index" => 4, "reason" => "oversized_for_sheet" }
      )
    end

    it "returns nil placements data when placements.json is invalid JSON" do
      project.placements_json.attach(
        io: StringIO.new("not-json"),
        filename: "placements.json",
        content_type: "application/json"
      )

      expect(described_class.for(project).items).to eq([])
    end
  end

  describe "orphan resolutions [REQ-FIT-SPLIT-001] [REQ-FIT-NEST-003]" do
    def attach_orphan_placements!(rows)
      project.nesting_runs.create!(
        status: "partial",
        report_json: { "orphans" => rows.map { |row| row.slice(:piece_index, :reason) } },
        finished_at: Time.current
      )
      project.placements_json.attach(
        io: StringIO.new({ sheets: [], orphans: rows }.to_json),
        filename: "placements.json",
        content_type: "application/json"
      )
    end

    it "[REQ-FIT-SPLIT-001] merges report orphans with OrphanResolution state" do
      attach_orphan_placements!(
        [
          {
            piece_index: 0,
            reason: "oversized_for_sheet",
            width_mm: 800.0,
            height_mm: 400.0,
            offset_x_mm: 0.0,
            offset_y_mm: 0.0,
            rings: [ [ [ 0.0, 0.0 ], [ 800.0, 0.0 ], [ 800.0, 400.0 ], [ 0.0, 400.0 ] ] ]
          },
          {
            piece_index: 1,
            reason: "no_sheet_capacity",
            width_mm: 120.0,
            height_mm: 50.0,
            offset_x_mm: 0.0,
            offset_y_mm: 0.0,
            rings: [ [ [ 0.0, 0.0 ], [ 120.0, 0.0 ], [ 120.0, 50.0 ], [ 0.0, 50.0 ] ] ]
          }
        ]
      )
      OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :pending
      )
      OrphanResolution.create!(
        project: project,
        piece_key: "1",
        reason: "no_sheet_capacity",
        resolution_state: :system_split
      )

      items = described_class.for(project).items

      expect(items.size).to eq(2)
      expect(items.find { |row| row.piece_index == 0 }.resolution_state).to eq("pending")
      expect(items.find { |row| row.piece_index == 1 }.resolution_state).to eq("system_split")
    end

    it "[REQ-FIT-SPLIT-001] excludes resolved orphans without derived pieces" do
      attach_orphan_placements!(
        [
          {
            piece_index: 0,
            reason: "oversized_for_sheet",
            width_mm: 100.0,
            height_mm: 50.0,
            offset_x_mm: 0.0,
            offset_y_mm: 0.0,
            rings: [ [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 100.0, 50.0 ], [ 0.0, 50.0 ] ] ]
          }
        ]
      )
      OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :resolved
      )

      expect(described_class.for(project).items).to be_empty
    end

    it "[REQ-FIT-SPLIT-001] keeps split-applied orphans visible until re-nest" do
      attach_orphan_placements!(
        [
          {
            piece_index: 0,
            reason: "oversized_for_sheet",
            width_mm: 100.0,
            height_mm: 50.0,
            offset_x_mm: 0.0,
            offset_y_mm: 0.0,
            rings: [ [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 100.0, 50.0 ], [ 0.0, 50.0 ] ] ]
          }
        ]
      )
      resolution = OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :resolved
      )
      resolution.split_proposals.create!(
        status: :accepted,
        version: 1,
        feasible: true,
        child_piece_geometries: [
          { "label" => "a", "rings" => [ [ [ 0.0, 0.0 ], [ 50.0, 0.0 ], [ 50.0, 30.0 ], [ 0.0, 30.0 ] ] ] }
        ],
        cut_segments: [],
        labels: [ "a" ]
      )
      project.derived_pieces.create!(
        parent_piece_key: "0",
        label: "Pieza-1a",
        geometry_json: { "rings" => [ [ [ 0.0, 0.0 ], [ 50.0, 0.0 ], [ 50.0, 30.0 ], [ 0.0, 30.0 ] ] ] },
        sort_order: 0
      )

      orphan = described_class.for(project).items.sole

      expect(orphan.split_applied?).to be(true)
    end

    it "[REQ-FIT-SPLIT-001] disables system_split when rings are not exportable" do
      attach_orphan_placements!(
        [
          {
            piece_index: 2,
            reason: "oversized_for_sheet",
            width_mm: 10.0,
            height_mm: 10.0,
            offset_x_mm: 0.0,
            offset_y_mm: 0.0,
            rings: []
          }
        ]
      )
      OrphanResolution.create!(
        project: project,
        piece_key: "2",
        reason: "oversized_for_sheet",
        resolution_state: :pending
      )

      orphan = described_class.for(project).items.sole

      expect(orphan.system_split_enabled?).to be(false)
      expect(orphan.exportable?).to be(false)
    end

    it "[REQ-FIT-SPLIT-001] surfaces split_not_feasible draft without preview actions" do
      attach_orphan_placements!(
        [
          {
            piece_index: 0,
            reason: "no_sheet_capacity",
            width_mm: 800.0,
            height_mm: 400.0,
            offset_x_mm: 0.0,
            offset_y_mm: 0.0,
            rings: [ [ [ 0.0, 0.0 ], [ 800.0, 0.0 ], [ 800.0, 400.0 ], [ 0.0, 400.0 ] ] ]
          }
        ]
      )
      resolution = OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "no_sheet_capacity",
        resolution_state: :system_split
      )
      resolution.split_proposals.create!(
        status: :draft,
        version: 1,
        feasible: false,
        plan_reason: "split_not_feasible",
        child_piece_geometries: [],
        cut_segments: [],
        labels: []
      )

      orphan = described_class.for(project).items.sole

      expect(orphan.split_not_feasible?).to be(true)
      expect(orphan.split_preview_available?).to be(false)
      expect(orphan.split_plan_failed?).to be(true)
    end
  end
end
