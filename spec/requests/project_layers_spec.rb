# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project layers", type: :request do
  let(:project) { create_project_for_spec!(title: "DXF upload bench") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "GET /projects/:project_id/layers [REQ-FIT-DXF-001]" do
    it "renders an empty checklist when no DXF files are attached" do
      get project_layers_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="layer-checklist"')
      expect(project.project_layers).to be_empty
    end

    it "shows a layer checklist built from union of uploaded DXF layer names" do
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
    it "uses legacy LayerSync when multiple DXFs have no per-file attachment ids" do
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece_a.dxf",
        content_type: "application/dxf"
      )
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece_b.dxf",
        content_type: "application/dxf"
      )
      project.project_layers.delete_all

      expect(Dxf::LayerSync).to receive(:call).with(project).and_call_original

      get project_layers_path(project)

      expect(response).to have_http_status(:ok)
      expect(project.project_layers.find_by!(layer_name: "PIECES")).to be_present
    end

    it "saves layer selection, starts nesting, and redirects to the project progress page" do
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
    let(:project) { create_project_for_spec!(title: "Composite layers bench") }

    def attach_per_file_dxf!
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
      expect(response.body).not_to include(I18n.t("project_layers.primary_layer.tooltip"))
    end

    it "shows blocking gap warning when a layer has gaps > 15mm" do
      gaps = [ { "distance_mm" => 20.0, "start" => [0, 0], "end" => [20, 0] } ]
      allow(Dxf::LayerNamesReader).to receive(:catalog).and_return(
        [ { "name" => "PIECES", "color" => "#808080", "gaps" => [] } ]
      )
      allow(Dxf::LayerNamesReader).to receive(:gaps_for).and_return(gaps)
      attachment = attach_per_file_dxf!
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      ProjectLayer::SetPrimary.call(layer)

      get project_layers_path(project)

      expect(response.body).to include("layer-gap-warning-#{layer.id}")
      expect(response.body).to include(I18n.t("project_layers.blocking_gap_warning", distance: 20.0))
      expect(response.body).not_to include("auto_close_gaps")
    end

    it "shows warnable gap warning and auto-close checkbox when a layer has gaps 2mm..15mm" do
      gaps = [ { "distance_mm" => 5.0, "start" => [0, 0], "end" => [5, 0] } ]
      allow(Dxf::LayerNamesReader).to receive(:catalog).and_return(
        [ { "name" => "PIECES", "color" => "#808080", "gaps" => [] } ]
      )
      allow(Dxf::LayerNamesReader).to receive(:gaps_for).and_return(gaps)
      attachment = attach_per_file_dxf!
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      ProjectLayer::SetPrimary.call(layer)

      get project_layers_path(project)

      expect(response.body).to include("layer-gap-warning-#{layer.id}")
      expect(response.body).to include(I18n.t("project_layers.warnable_gap_warning", distance: 5.0))
      expect(response.body).to include("auto_close_gaps")
    end

    it "does not show blocking gap on unselected MARCADO when CORTE is primary" do
      dxf_015 = Rails.root.join("nesting_engine/tests/fixtures/individuals/015.dxf")
      project.input_dxf.attach(
        io: File.open(dxf_015),
        filename: "015.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSyncPerFile.call(project)
      attachment = project.input_dxf_attachments.first!
      corte = project.project_layers.find_by!(
        layer_name: "CORTE",
        active_storage_attachment_id: attachment.id
      )
      marcado = project.project_layers.find_by!(
        layer_name: "MARCADO",
        active_storage_attachment_id: attachment.id
      )

      ProjectLayer::SetPrimary.call(corte)

      expect(marcado.reload.gaps_detected).to eq([])

      get project_layers_path(project)

      expect(response.body).not_to include(
        I18n.t("project_layers.blocking_gap_warning", distance: 158.1)
      )
      expect(response.body).not_to include("layer-gap-warning-#{marcado.id}")
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

    it "PATCH clears auxiliary when the checkbox is unchecked" do
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

      expect(gravado.reload).to have_attributes(layer_role: "auxiliary", included: true)

      patch project_layers_path(project), params: {
        project_layers: {
          attachment.id.to_s => {
            primary_layer_id: cut.id.to_s
          }
        }
      }

      expect(gravado.reload).to have_attributes(layer_role: nil, included: false)
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
    let(:project) { create_project_for_spec!(title: "DXF multi-upload bench") }

    it "accepts multiple DXF uploads in one request" do
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

  describe "PATCH /projects/:project_id/layers with active pending payment lock [REQ-FIT-BILL-001]" do
    let(:user) { create_billing_user!(email: "lock-layers@example.com") }

    before do
      sign_in user
    end

    it "blocks layer mutation and redirects to workshop when payment is pending" do
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      Dxf::LayerSync.call(project)
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      run = project.nesting_runs.create!(status: "completed")

      # Create active pending SINPE payment
      Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_lock_layers_test",
        onvo_mode: "test",
        gateway_status: "processing",
        created_at: 1.minute.ago
      )

      # Bind workspace to session/user
      get workshop_path, headers: { "HTTP_X_WORKSPACE_TAB_ID" => Workspace::DEFAULT_TAB_ID }

      patch project_layers_path(project), params: {
        project_layers: { layer.id.to_s => { included: "1" } }
      }

      expect(response).to redirect_to(workshop_path)
      expect(flash[:alert]).to be_present
      expect(layer.reload).not_to be_included
    end
  end
end
