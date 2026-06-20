# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectLayerSelection, "[REQ-FIT-DXF-002]" do
  let(:project) { ProjectSpecFactory.create!(title: "Layer selection service") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def attach_per_file_dxf!
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    Dxf::LayerSyncPerFile.call(project)
    project.input_dxf_attachments.first!
  end

  it "no-ops when params are blank" do
    attachment = attach_per_file_dxf!
    layer = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
    layer.update!(included: true)

    described_class.apply!(project: project, raw_params: {})

    expect(layer.reload).to be_included
  end

  it "accepts ActionController::Parameters" do
    attachment = attach_per_file_dxf!
    cut = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
    params = ActionController::Parameters.new(
      project_layers: {
        attachment.id.to_s => { primary_layer_id: cut.id.to_s }
      }
    )

    described_class.apply!(project: project, raw_params: params[:project_layers])

    expect(cut.reload.layer_role).to eq("primary")
  end

  it "applies flat included checkboxes by layer id" do
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    Dxf::LayerSync.call(project)
    layer = project.project_layers.find_by!(layer_name: "PIECES")
    layer.update!(included: false)

    described_class.apply!(
      project: project,
      raw_params: { layer.id.to_s => { included: "1" } }
    )

    expect(layer.reload).to be_included
  end

  it "clears primaries on an attachment when grouped params omit primary_layer_id" do
    attachment = attach_per_file_dxf!
    cut = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
    cut.update!(layer_role: "primary", included: true)

    described_class.apply!(
      project: project,
      raw_params: {
        attachment.id.to_s => { cut.id.to_s => { auxiliary: "0" } }
      }
    )

    expect(cut.reload).to have_attributes(layer_role: nil, included: false)
  end

  it "skips grouped attachment entries that are not hashes" do
    attachment = attach_per_file_dxf!
    cut = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
    cut.update!(layer_role: "primary", included: true)

    described_class.apply!(
      project: project,
      raw_params: {
        attachment.id.to_s => "invalid"
      }
    )

    expect(cut.reload.layer_role).to eq("primary")
  end

  it "raises when the primary layer id does not belong to the attachment" do
    first_attachment = attach_per_file_dxf!
    attach_per_file_dxf!
    second_attachment = project.input_dxf_attachments.order(:id).last!
    foreign_cut = project.project_layers.find_by!(
      layer_name: "PIECES",
      active_storage_attachment_id: second_attachment.id
    )

    expect do
      described_class.apply!(
        project: project,
        raw_params: {
          first_attachment.id.to_s => { primary_layer_id: foreign_cut.id.to_s }
        }
      )
    end.to raise_error(ArgumentError, "primary layer not found")
  end
end
