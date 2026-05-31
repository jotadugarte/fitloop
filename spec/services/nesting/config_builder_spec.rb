# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ConfigBuilder, "[REQ-FIT-CLI-001]" do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }
  let(:work_dir) { Rails.root.join("tmp/test_config_builder_composite") }

  describe "input_files composite layers [REQ-FIT-DXF-002] [REQ-FIT-CLI-001]" do
    def build_payload_for_attached_dxf!
      project = Project.create!(
        ephemeral: true,
        status: :ready,
        title: "Composite config",
        kerf_mm: 0,
        margin_mm: 5,
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      )
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.reload

      input_path = work_dir.join("piece.dxf")
      FileUtils.mkdir_p(work_dir)
      FileUtils.cp(sample_dxf, input_path)

      payload = described_class.build(
        project: project,
        work_dir: work_dir,
        input_paths: [ input_path ]
      )

      [ project, payload.fetch(:input_files).first ]
    end

    it "emits primary_layer and auxiliary_layers when primary is configured" do
      project = Project.create!(
        ephemeral: true,
        status: :ready,
        title: "Composite config primary",
        kerf_mm: 0,
        margin_mm: 5,
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      )
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      attachment = project.input_dxf_attachments.first!
      cut = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment.id
      )
      project.project_layers.create!(
        layer_name: "GRABADO",
        active_storage_attachment_id: attachment.id,
        included: true,
        layer_role: :auxiliary
      )
      ProjectLayer::SetPrimary.call(cut)

      input_path = work_dir.join("piece-primary.dxf")
      FileUtils.mkdir_p(work_dir)
      FileUtils.cp(sample_dxf, input_path)
      file_entry = described_class.build(
        project: project.reload,
        work_dir: work_dir,
        input_paths: [ input_path ]
      ).fetch(:input_files).first

      expect(file_entry).to include(
        primary_layer: "PIECES",
        auxiliary_layers: [ "GRABADO" ]
      )
      expect(file_entry).not_to have_key(:included_layers)
    end

    it "emits included_layers when no primary is set on the file" do
      project = Project.create!(
        ephemeral: true,
        status: :ready,
        title: "Composite config legacy",
        kerf_mm: 0,
        margin_mm: 5,
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      )
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      attachment = project.input_dxf_attachments.first!
      project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment.id
      ).update!(included: true, layer_role: nil)

      input_path = work_dir.join("piece-legacy.dxf")
      FileUtils.mkdir_p(work_dir)
      FileUtils.cp(sample_dxf, input_path)
      file_entry = described_class.build(
        project: project.reload,
        work_dir: work_dir,
        input_paths: [ input_path ]
      ).fetch(:input_files).first

      expect(file_entry).to include(included_layers: [ "PIECES" ])
      expect(file_entry).not_to have_key(:primary_layer)
      expect(file_entry).not_to have_key(:auxiliary_layers)
    end
  end

  it "[REQ-FIT-CLI-001] merges JobParameters numerics into the CLI payload" do
    project = create_project_for_spec!(
      title: "Config builder numerics",
      bind_workspace: false,
      kerf_mm: 1.5,
      margin_mm: 6,
      curve_tolerance_mm: 0.2,
      sheet_gap_mm: 12,
      nesting_time_limit_sec: 450
    )

    payload = described_class.build(
      project: project,
      work_dir: Rails.root.join("tmp/test_config_builder_numerics"),
      input_paths: []
    )

    expect(payload).to include(Nesting::JobParameters.from_project(project).to_config_hash)
  end

  it "[REQ-FIT-NEST-002] passes all persisted sheet stocks to the CLI in consumption order" do
    project = Project.create!(
      ephemeral: true,
      status: :ready,
      title: "Config builder",
      kerf_mm: 0,
      margin_mm: 5,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 },
        "1" => { width_mm: 1000, height_mm: 1000, quantity: 10, sort_order: 1 }
      }
    )

    payload = described_class.build(
      project: project,
      work_dir: Rails.root.join("tmp/test_config_builder"),
      input_paths: []
    )

    expect(payload.fetch(:sheet_stocks).size).to eq(2)
    expect(payload.fetch(:sheet_stocks).first).to include(
      width_mm: 1000.0,
      height_mm: 2000.0,
      quantity: 1,
      sort_order: 0
    )
    expect(payload.fetch(:sheet_stocks).last).to include(
      width_mm: 1000.0,
      height_mm: 1000.0,
      quantity: 10,
      sort_order: 1
    )
  end
end
