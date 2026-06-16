# frozen_string_literal: true

require "rails_helper"

RSpec.describe Dxf::LayerGapScanner, "[REQ-FIT-DXF-002]" do
  let(:project) { create_project_for_spec!(title: "Gap scanner bench") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def attach_sample_dxf!
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    Dxf::LayerSyncPerFile.call(project)
    project.input_dxf_attachments.first!
  end

  describe ".refresh!" do
    it "scans gaps when the layer requires closed-contour validation" do
      gaps = [ { "distance_mm" => 5.0, "start" => [0.0, 0.0], "end" => [5.0, 0.0] } ]
      allow(Dxf::LayerNamesReader).to receive(:gaps_for).and_return(gaps)
      attach_sample_dxf!
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      ProjectLayer::SetPrimary.call(layer)

      expect(layer.reload.gaps_detected).to eq(gaps)
    end

    it "clears gaps for auxiliary layers" do
      attachment_id = attach_sample_dxf!
      layer = project.project_layers.create!(
        layer_name: "GRABADO",
        active_storage_attachment_id: attachment_id,
        included: true,
        layer_role: :auxiliary,
        gaps_detected: [ { "distance_mm" => 20.0, "start" => [0.0, 0.0], "end" => [20.0, 0.0] } ]
      )

      described_class.refresh!(layer)

      expect(layer.reload.gaps_detected).to eq([])
    end

    it "clears gaps for unselected cut layers" do
      attachment_id = attach_sample_dxf!
      layer = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment_id
      )
      layer.update!(
        gaps_detected: [ { "distance_mm" => 20.0, "start" => [0.0, 0.0], "end" => [20.0, 0.0] } ]
      )

      described_class.refresh!(layer)

      expect(layer.reload.gaps_detected).to eq([])
    end
  end

  describe ".clear!" do
    it "no-ops when gaps_detected is already empty" do
      attachment_id = attach_sample_dxf!
      layer = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment_id
      )

      expect { described_class.clear!(layer) }.not_to change { layer.reload.gaps_detected }
    end
  end
end
