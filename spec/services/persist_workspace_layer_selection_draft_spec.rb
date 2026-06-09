# frozen_string_literal: true

require "rails_helper"

RSpec.describe PersistWorkspaceLayerSelectionDraft, "[REQ-FIT-UI-005]" do
  let(:project) { ProjectSpecFactory.create!(title: "Layer selection draft") }
  let(:session) { { Workspace::SESSION_KEY => project.id } }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def attach_dxf!
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    Dxf::LayerSyncPerFile.call(project)
    project.input_dxf_attachments.first!
  end

  it "returns false when the session has no bound project" do
    result = described_class.call(session: {}, params: { project_layers: {} })

    expect(result).to be(false)
  end

  it "returns false when project_layers are blank" do
    result = described_class.call(session: session, params: {})

    expect(result).to be(false)
  end

  it "returns false when layer params would wipe an existing configuration" do
    attachment = attach_dxf!
    cut = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
    cut.update!(layer_role: "primary", included: true)

    result = described_class.call(
      session: session,
      params: {
        project_layers: {
          attachment.id.to_s => {}
        }
      }
    )

    expect(result).to be(false)
    expect(cut.reload.layer_role).to eq("primary")
  end

  it "persists primary and auxiliary picks from a plain hash payload" do
    attachment = attach_dxf!
    cut = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
    gravado = project.project_layers.create!(
      layer_name: "GRABADO",
      active_storage_attachment_id: attachment.id,
      included: false
    )

    result = described_class.call(
      session: session,
      params: {
        project_layers: {
          attachment.id.to_s => {
            primary_layer_id: cut.id.to_s,
            gravado.id.to_s => { auxiliary: "1" }
          }
        }
      }
    )

    expect(result).to be(true)
    expect(cut.reload).to have_attributes(layer_role: "primary", included: true)
    expect(gravado.reload).to have_attributes(layer_role: "auxiliary", included: true)
  end

  it "accepts ActionController::Parameters and resolves the preferred tab bind" do
    attachment = attach_dxf!
    cut = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
    tab_id = "tab-layer-draft"
    tab_session = {
      Workspace::WORKSPACES_KEY => { tab_id => project.id }
    }
    permitted = ActionController::Parameters.new(
      project_layers: {
        attachment.id.to_s => { primary_layer_id: cut.id.to_s }
      }
    ).permit!

    result = described_class.call(session: tab_session, params: permitted, tab_id: tab_id)

    expect(result).to be(true)
    expect(cut.reload.layer_role).to eq("primary")
  end

  it "allows clearing roles when no layer was configured yet" do
    attachment = attach_dxf!
    cut = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)

    result = described_class.call(
      session: session,
      params: {
        project_layers: {
          attachment.id.to_s => { primary_layer_id: cut.id.to_s }
        }
      }
    )

    expect(result).to be(true)
    expect(cut.reload.layer_role).to eq("primary")
  end
end
