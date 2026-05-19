# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dxf::PieceCounter do
  let(:composite_fixture) do
    Rails.root.join("nesting_engine/tests/fixtures/composite-piece-count.dxf")
  end

  describe ".layer_names_for_count [REQ-FIT-DXF-002]" do
    let(:project) { create_project_for_spec!(title: "Piece count", pin: "112233", bind_workspace: false) }

    def layers_for(attachment_id)
      project.project_layers.where(
        included: true,
        active_storage_attachment_id: attachment_id
      )
    end

    it "returns only the primary layer name when a primary is set on the file" do
      attachment_id = 42
      project.project_layers.create!(
        layer_name: "CORTE",
        active_storage_attachment_id: attachment_id,
        included: true,
        layer_role: :primary
      )
      project.project_layers.create!(
        layer_name: "GRABADO",
        active_storage_attachment_id: attachment_id,
        included: true,
        layer_role: :auxiliary
      )

      expect(described_class.layer_names_for_count(layers_for(attachment_id))).to eq([ "CORTE" ])
    end

    it "returns all included layer names in legacy mode without a primary" do
      attachment_id = 42
      project.project_layers.create!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment_id,
        included: true,
        layer_role: nil
      )

      expect(described_class.layer_names_for_count(layers_for(attachment_id))).to eq([ "PIECES" ])
    end
  end

  describe ".count [REQ-FIT-DXF-002]" do
    it "counts only primary layer polygons when primary role is configured" do
      primary_only = [ "CORTE" ]
      all_included = %w[CORTE GRABADO]

      expect(
        described_class.count(paths: [ composite_fixture ], layer_names: primary_only)
      ).to eq(2)
      expect(
        described_class.count(paths: [ composite_fixture ], layer_names: all_included)
      ).to eq(3)
    end
  end
end
