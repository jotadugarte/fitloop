# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ConfigBuilder do
  describe "split payload [REQ-FIT-CLI-001] [REQ-FIT-SPLIT-001]" do
    it "[REQ-FIT-SPLIT-001] includes excluded_piece_keys and derived_pieces after accept" do
      project = Project.create!(
        ephemeral: true,
        status: :ready,
        title: "Split config",
        kerf_mm: 0,
        margin_mm: 5,
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      )
      resolution = OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :resolved
      )
      project.derived_pieces.create!(
        parent_piece_key: "0",
        label: "Pieza-1a",
        geometry_json: {
          "rings" => [ [ [ 0.0, 0.0 ], [ 80.0, 0.0 ], [ 80.0, 40.0 ], [ 0.0, 40.0 ] ] ]
        },
        sort_order: 0
      )
      project.derived_pieces.create!(
        parent_piece_key: "0",
        label: "Pieza-1b",
        geometry_json: {
          "rings" => [ [ [ 80.0, 0.0 ], [ 160.0, 0.0 ], [ 160.0, 40.0 ], [ 80.0, 40.0 ] ] ]
        },
        sort_order: 1
      )
      SplitProposal.create!(
        orphan_resolution: resolution,
        status: :accepted,
        version: 1,
        labels: %w[a b],
        child_piece_geometries: [],
        cut_segments: [ [ [ 80.0, 0.0 ], [ 80.0, 40.0 ] ] ]
      )

      payload = described_class.build(
        project: project,
        work_dir: Rails.root.join("tmp/test_config_builder_split"),
        input_paths: []
      )

      expect(payload.fetch(:excluded_piece_keys)).to eq([ "0" ])
      derived = payload.fetch(:derived_pieces)
      expect(derived.size).to eq(2)
      expect(derived.first).to include(
        parent_piece_key: "0",
        label: "Pieza-1a",
        sort_order: 0
      )
      expect(derived.first.fetch(:rings)).to be_present
      expect(payload.fetch(:split_cut_segments)).to eq([ [ [ 80.0, 0.0 ], [ 80.0, 40.0 ] ] ])
    end

    it "[REQ-FIT-DXF-002] [REQ-FIT-SPLIT-001] includes decorations and primary_layer_name for derived pieces" do
      project = Project.create!(
        ephemeral: true,
        status: :ready,
        title: "Split config composite",
        kerf_mm: 0,
        margin_mm: 5,
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      )
      OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :resolved
      )
      project.derived_pieces.create!(
        parent_piece_key: "0",
        label: "Pieza-1a",
        geometry_json: {
          "rings" => [ [ [ 0.0, 0.0 ], [ 80.0, 0.0 ], [ 80.0, 40.0 ], [ 0.0, 40.0 ] ] ],
          "primary_layer_name" => "CORTE"
        },
        decorations_json: [
          {
            "layer_name" => "GRABADO",
            "geometry_type" => "line",
            "payload" => { "coordinates" => [ [ 5.0, 20.0 ], [ 75.0, 20.0 ] ] }
          }
        ],
        sort_order: 0
      )

      payload = described_class.build(
        project: project,
        work_dir: Rails.root.join("tmp/test_config_builder_split_decorations"),
        input_paths: []
      )

      derived = payload.fetch(:derived_pieces).sole
      expect(derived.fetch(:primary_layer_name)).to eq("CORTE")
      expect(derived.fetch(:decorations).sole).to include(
        "layer_name" => "GRABADO",
        "geometry_type" => "line"
      )
    end

    it "[REQ-FIT-SPLIT-001] omits split keys when no derived pieces exist" do
      project = Project.create!(
        ephemeral: true,
        status: :ready,
        title: "No split",
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      )

      payload = described_class.build(
        project: project,
        work_dir: Rails.root.join("tmp/test_config_builder_plain"),
        input_paths: []
      )

      expect(payload).not_to have_key(:excluded_piece_keys)
      expect(payload).not_to have_key(:derived_pieces)
    end
  end
end
