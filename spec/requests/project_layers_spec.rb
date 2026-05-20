# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project layers", type: :request do
  let(:project) { create_project_for_spec!(title: "DXF upload bench", pin: "445566") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "GET /projects/:project_id/layers [REQ-FIT-DXF-001]" do
    it "shows a layer checklist built from union of uploaded DXF layer names" do
      unlock_project_for_spec!(project, pin: "445566")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece_a.dxf",
        content_type: "application/dxf"
      )

      get project_layers_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="layer-checklist"')
      expect(response.body).to include("PIECES")
    end
  end

  describe "PATCH /projects/:project_id/layers [REQ-FIT-DXF-001]" do
    it "saves layer selection, starts nesting, and redirects to the project progress page" do
      unlock_project_for_spec!(project, pin: "445566")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSync.call(project)
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      layer.update!(included: false)

      expect do
        patch project_layers_path(project), params: {
          project_layers: { layer.id.to_s => { included: "1" } }
        }
      end.to have_enqueued_job(NestingJob)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to be_nil
      expect(layer.reload).to be_included
      expect(project.reload.status).to eq("processing")
    end
  end

  describe "composite layer UI [REQ-FIT-DXF-002]" do
    let(:project) do
      create_project_for_spec!(
        title: "Composite layers bench",
        pin: "445566",
        ephemeral: false,
        bind_workspace: false
      )
    end

    def attach_per_file_dxf!
      unlock_project_for_spec!(project, pin: "445566")
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      project.input_dxf_attachments.first!
    end

    it "shows primary layer radio grouped per DXF file" do
      attach_per_file_dxf!

      get project_layers_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="dxf-file-layers"')
      expect(response.body).to include('data-testid="primary-layer-radio"')
      expect(response.body).to include(I18n.t("project_layers.primary_layer.short"))
      expect(response.body).to include(I18n.t("project_layers.auxiliary_layers.short"))
      expect(response.body).to include('data-testid="dxf-file-layers-meta"')
      expect(response.body).not_to include(I18n.t("project_layers.primary_layer.tooltip"))
    end

    it "PATCH sets exclusive primary and auxiliary roles per attachment" do
      attachment = attach_per_file_dxf!
      cut = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment.id
      )
      gravado = project.project_layers.create!(
        layer_name: "GRABADO",
        active_storage_attachment_id: attachment.id,
        included: false
      )

      patch project_layers_path(project), params: {
        project_layers: {
          attachment.id.to_s => {
            primary_layer_id: cut.id.to_s,
            gravado.id.to_s => { auxiliary: "1" }
          }
        }
      }

      expect(response).to redirect_to(project_path(project))
      expect(cut.reload).to have_attributes(layer_role: "primary", included: true)
      expect(gravado.reload).to have_attributes(layer_role: "auxiliary", included: true)
    end

    it "PATCH ignores auxiliary when the same layer is chosen as primary" do
      attachment = attach_per_file_dxf!
      cut = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment.id
      )

      patch project_layers_path(project), params: {
        project_layers: {
          attachment.id.to_s => {
            primary_layer_id: cut.id.to_s,
            cut.id.to_s => { auxiliary: "1" }
          }
        }
      }

      expect(response).to redirect_to(project_path(project))
      expect(cut.reload).to have_attributes(layer_role: "primary", included: true)
    end

    it "PATCH switching primary clears the previous primary on the same attachment" do
      attachment = attach_per_file_dxf!
      cut = project.project_layers.find_by!(
        layer_name: "PIECES",
        active_storage_attachment_id: attachment.id
      )
      outline = project.project_layers.create!(
        layer_name: "OUTLINE",
        active_storage_attachment_id: attachment.id,
        included: false
      )
      ProjectLayer::SetPrimary.call(cut)

      patch project_layers_path(project), params: {
        project_layers: {
          attachment.id.to_s => {
            primary_layer_id: outline.id.to_s
          }
        }
      }

      expect(cut.reload.layer_role).to be_nil
      expect(outline.reload).to have_attributes(layer_role: "primary", included: true)
    end
  end

  describe "POST /projects/:project_id/input_dxf_files [REQ-FIT-DXF-001]" do
    # Saved project: avoids ephemeral workspace session coupling (resolve! requires bound session).
    let(:project) do
      create_project_for_spec!(
        title: "DXF multi-upload bench",
        pin: "445566",
        ephemeral: false,
        bind_workspace: false
      )
    end

    it "accepts multiple DXF uploads in one request" do
      unlock_project_for_spec!(project, pin: "445566")

      post project_input_dxf_files_path(project), params: {
        files: [
          fixture_file_upload(sample_dxf, "first.dxf", "application/dxf"),
          fixture_file_upload(sample_dxf, "second.dxf", "application/dxf")
        ]
      }

      expect(response).to redirect_to(project_path(project))
      expect(project.reload.input_dxf.count).to eq(2)
    end
  end
end
