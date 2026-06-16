# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectLayer, type: :model do
  let(:project) { create_project_for_spec!(title: "Layer roles", bind_workspace: false) }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def sync_layers_from_sample_dxf!
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    Dxf::LayerSyncPerFile.call(project)
    project.input_dxf_attachments.first!.id
  end

  describe "associations [REQ-FIT-DOM-001]" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end
  end

  describe "layer filter [REQ-FIT-DOM-001]" do
    it "stores layer_name and included flag" do
      layer = described_class.new(layer_name: "PIECES", included: true)

      expect(layer.layer_name).to eq("PIECES")
      expect(layer.included).to be(true)
    end
  end

  describe "layer_role [REQ-FIT-DXF-002] [REQ-FIT-DOM-001]" do
    let(:attachment_id) { sync_layers_from_sample_dxf! }

    def layer_named(name)
      project.project_layers.find_by!(
        layer_name: name,
        active_storage_attachment_id: attachment_id
      )
    end

    it "defaults layer_role to nil" do
      expect(layer_named("PIECES").layer_role).to be_nil
    end

    it "allows primary and auxiliary roles" do
      cut = layer_named("PIECES")
      engrave = project.project_layers.create!(
        layer_name: "GRABADO",
        active_storage_attachment_id: attachment_id,
        included: false
      )

      cut.update!(layer_role: :primary)
      engrave.update!(layer_role: :auxiliary)

      expect(cut.reload).to have_attributes(layer_role: "primary")
      expect(engrave.reload).to have_attributes(layer_role: "auxiliary")
    end

    it "rejects a second primary on the same attachment" do
      cut = layer_named("PIECES")
      outline = project.project_layers.create!(
        layer_name: "OUTLINE",
        active_storage_attachment_id: attachment_id,
        included: false
      )

      cut.update!(layer_role: :primary)

      outline.layer_role = :primary
      expect(outline).not_to be_valid
      expect(outline.errors[:layer_role]).to be_present
    end

    describe "ProjectLayer::SetPrimary" do
      it "clears other primaries on the same attachment" do
        cut = layer_named("PIECES")
        outline = project.project_layers.create!(
          layer_name: "OUTLINE",
          active_storage_attachment_id: attachment_id,
          included: false,
          layer_role: :primary
        )

        described_class.set_primary!(cut)

        expect(cut.reload).to have_attributes(layer_role: "primary")
        expect(outline.reload.layer_role).to be_nil
      end

      it "sets included when marking primary" do
        cut = layer_named("PIECES")
        cut.update!(included: false)

        ProjectLayer::SetPrimary.call(cut)

        expect(cut.reload).to have_attributes(layer_role: "primary", included: true)
      end

      it "allows one primary per attachment when files differ" do
        second_path = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
        project.input_dxf.attach(
          io: File.open(second_path),
          filename: "piece_b.dxf",
          content_type: "application/dxf"
        )
        Dxf::LayerSyncPerFile.call(project)

        first_cut = layer_named("PIECES")
        second_attachment_id = project.input_dxf_attachments.order(:id).last!.id
        second_cut = project.project_layers.find_by!(
          layer_name: "PIECES",
          active_storage_attachment_id: second_attachment_id
        )

        ProjectLayer::SetPrimary.call(first_cut)
        ProjectLayer::SetPrimary.call(second_cut)

        expect(first_cut.reload.layer_role).to eq("primary")
        expect(second_cut.reload.layer_role).to eq("primary")
      end
    end
  end

  describe "syncing layers with gaps [REQ-FIT-DXF-001]" do
    it "defers gaps at sync and refreshes when primary is set" do
      gaps = [ { "distance_mm" => 5.0, "start" => [0.0, 0.0], "end" => [5.0, 0.0] } ]
      allow(Dxf::LayerNamesReader).to receive(:catalog).and_return(
        [ { "name" => "PIECES", "color" => "#ffffff", "gaps" => [] } ]
      )
      allow(Dxf::LayerNamesReader).to receive(:gaps_for).and_return(gaps)

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)

      layer = project.project_layers.find_by!(layer_name: "PIECES")
      expect(layer.gaps_detected).to eq([])

      ProjectLayer::SetPrimary.call(layer)

      expect(layer.reload.gaps_detected).to eq(gaps)
    end
  end

  describe "#closed_contour_gap_validation? [REQ-FIT-DXF-002]" do
    let(:attachment_id) { sync_layers_from_sample_dxf! }

    it "is true for primary layers" do
      layer = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment_id
      )
      layer.update!(layer_role: :primary, included: true)

      expect(layer.closed_contour_gap_validation?).to be(true)
    end

    it "is false for auxiliary and unselected layers" do
      marcado = project.project_layers.create!(
        layer_name: "MARCADO",
        active_storage_attachment_id: attachment_id,
        included: true,
        layer_role: :auxiliary
      )
      idle = project.project_layers.create!(
        layer_name: "DEFPOINTS",
        active_storage_attachment_id: attachment_id,
        included: false
      )

      expect(marcado.closed_contour_gap_validation?).to be(false)
      expect(idle.closed_contour_gap_validation?).to be(false)
    end
  end
end
