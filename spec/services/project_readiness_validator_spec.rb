# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectReadinessValidator, "[REQ-FIT-VAL-001]" do
  let(:project) { create_project_for_spec!(title: "Pre-flight bench") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def attach_sample_dxf!
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    Dxf::LayerSync.call(project)
  end

  describe ".validate [REQ-FIT-VAL-001]" do
    it "rejects when no sheet stocks exist" do
      project = create_project_for_spec!(title: "No sheets")
      project.sheet_stocks.destroy_all

      result = described_class.validate(project)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("project_readiness.no_sheet_stocks"))
    end

    it "rejects when no layers are selected" do
      attach_sample_dxf!
      project.project_layers.update_all(included: false)

      result = described_class.validate(project)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("project_readiness.no_layers_selected"))
    end

    it "rejects when layers are selected but no extractable pieces exist" do
      attach_sample_dxf!
      project.project_layers.update_all(included: false)
      project.project_layers.create!(layer_name: "EMPTY_LAYER", included: true)

      result = described_class.validate(project)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("project_readiness.no_extractable_pieces"))
    end

    it "accepts when at least one layer is selected and pieces exist" do
      attach_sample_dxf!
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true)

      result = described_class.validate(project)

      expect(result.ok?).to be(true)
      expect(result.errors).to be_empty
    end

    it "rejects when layers have blocking gaps (> 15.0 mm)" do
      attach_sample_dxf!
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      layer.update!(
        included: true,
        gaps_detected: [{ "distance_mm" => 20.0, "start" => [0.0, 0.0], "end" => [20.0, 0.0] }],
        auto_close_gaps: true
      )

      result = described_class.validate(project)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("project_readiness.unresolved_gaps"))
    end

    it "rejects when layers have medium gaps (2.0 - 15.0 mm) without auto_close_gaps enabled" do
      attach_sample_dxf!
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      layer.update!(
        included: true,
        gaps_detected: [{ "distance_mm" => 5.0, "start" => [0.0, 0.0], "end" => [5.0, 0.0] }],
        auto_close_gaps: false
      )

      result = described_class.validate(project)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("project_readiness.unresolved_gaps"))
    end

    it "accepts when layers have medium gaps (2.0 - 15.0 mm) with auto_close_gaps enabled" do
      attach_sample_dxf!
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      layer.update!(
        included: true,
        gaps_detected: [{ "distance_mm" => 5.0, "start" => [0.0, 0.0], "end" => [5.0, 0.0] }],
        auto_close_gaps: true
      )

      result = described_class.validate(project)

      expect(result.ok?).to be(true)
      expect(result.errors).to be_empty
    end

    it "accepts when layers have only small gaps (<= 2.0 mm) regardless of auto_close_gaps" do
      attach_sample_dxf!
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      layer.update!(
        included: true,
        gaps_detected: [{ "distance_mm" => 1.5, "start" => [0.0, 0.0], "end" => [1.5, 0.0] }],
        auto_close_gaps: false
      )

      result = described_class.validate(project)

      expect(result.ok?).to be(true)
      expect(result.errors).to be_empty
    end
  end

  describe "composite layer roles [REQ-FIT-DXF-002] [REQ-FIT-VAL-001]" do
    def attach_and_sync_per_file!
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.input_dxf_attachments.first!.id
    end

    it "rejects when auxiliary is included without primary on the same attachment" do
      attachment_id = attach_and_sync_per_file!
      project.project_layers.create!(
        layer_name: "GRABADO",
        active_storage_attachment_id: attachment_id,
        included: true,
        layer_role: :auxiliary
      )

      result = described_class.validate(project)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("project_readiness.primary_layer_required"))
    end

    it "accepts when primary is set and included on the same attachment" do
      attachment_id = attach_and_sync_per_file!
      cut = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment_id
      )
      ProjectLayer::SetPrimary.call(cut)

      result = described_class.validate(project)

      expect(result.ok?).to be(true)
      expect(result.errors).to be_empty
    end

    it "accepts when auxiliary layer stores blocking gaps that are not cut-contour validation" do
      attachment_id = attach_and_sync_per_file!
      cut = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment_id
      )
      ProjectLayer::SetPrimary.call(cut)
      project.project_layers.create!(
        layer_name: "MARCADO",
        active_storage_attachment_id: attachment_id,
        included: true,
        layer_role: :auxiliary,
        gaps_detected: [
          { "distance_mm" => 158.1, "start" => [0.0, 0.0], "end" => [158.1, 0.0] }
        ]
      )

      result = described_class.validate(project)

      expect(result.ok?).to be(true)
      expect(result.errors).to be_empty
    end

    it "accepts legacy per-file mode when only included layers have no layer_role" do
      attachment_id = attach_and_sync_per_file!
      project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment_id
      ).update!(included: true, layer_role: nil)

      result = described_class.validate(project)

      expect(result.ok?).to be(true)
      expect(result.errors).to be_empty
    end

    it "counts only primary layer contours when primary and auxiliary are included" do
      composite_fixture = Rails.root.join("nesting_engine/tests/fixtures/composite-piece-count.dxf")
      project.input_dxf.attach(
        io: File.open(composite_fixture),
        filename: "composite-piece-count.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      attachment_id = project.input_dxf_attachments.first!.id
      cut = project.project_layers.find_by!(
        layer_name: "CORTE",
        active_storage_attachment_id: attachment_id
      )
      ProjectLayer::SetPrimary.call(cut)
      project.project_layers.find_by!(
        layer_name: "GRABADO",
        active_storage_attachment_id: attachment_id
      ).update!(included: true, layer_role: :auxiliary)

      result = described_class.validate(project)

      expect(result.ok?).to be(true)
      expect(result.errors).to be_empty
    end
  end

  describe "extractable piece counting branches [REQ-FIT-VAL-001]" do
    it "returns zero extractable pieces when union layer names are empty" do
      attach_sample_dxf!
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true)
      allow(Dxf::PieceCounter).to receive(:layer_names_for_count).and_return([])

      result = described_class.validate(project)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("project_readiness.no_extractable_pieces"))
    end

    it "returns zero when downloaded DXF paths are blank in union mode" do
      attach_sample_dxf!
      project.project_layers.find_by!(layer_name: "PIECES").update!(included: true)
      validator = described_class.new(project)
      allow(validator).to receive(:with_downloaded_dxf_paths).and_yield([])

      expect(validator.send(:extractable_piece_count)).to eq(0)
    end

    it "skips per-file attachments with no selected layer names" do
      composite_fixture = Rails.root.join("nesting_engine/tests/fixtures/composite-piece-count.dxf")
      project.input_dxf.attach(
        io: File.open(composite_fixture),
        filename: "composite-piece-count.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.update_all(included: false)

      result = described_class.validate(project)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("project_readiness.no_layers_selected"))
    end
  end
end
