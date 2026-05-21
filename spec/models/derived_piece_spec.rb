# frozen_string_literal: true

require "rails_helper"

RSpec.describe DerivedPiece do
  let(:project) { create_project_for_spec!(title: "Derived") }

  describe "#display_suffix [REQ-FIT-SPLIT-001]" do
    it "uppercases the letter suffix from Pieza-Nx labels" do
      piece = project.derived_pieces.create!(
        parent_piece_key: "0",
        label: "Pieza-1a",
        geometry_json: { "rings" => [] },
        sort_order: 0
      )

      expect(piece.display_suffix).to eq("A")
    end
  end

  describe "#bounding_box_mm [REQ-FIT-SPLIT-001]" do
    it "returns axis-aligned bounds from ring vertices" do
      piece = project.derived_pieces.create!(
        parent_piece_key: "0",
        label: "Pieza-1b",
        geometry_json: {
          "rings" => [ [ [ 100.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 50.0 ], [ 100.0, 50.0 ] ] ]
        },
        sort_order: 1
      )

      expect(piece.bounding_width_mm).to eq(100.0)
      expect(piece.bounding_height_mm).to eq(50.0)
    end
  end
end
