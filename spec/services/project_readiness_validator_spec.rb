# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectReadinessValidator do
  let(:project) { create_project_for_spec!(title: "Pre-flight bench", pin: "112233") }
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
  end
end
