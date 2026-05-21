# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project workspace layers (Tu anidado)", type: :request do
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def ready_workspace_project!
    get start_project_path
    follow_redirect!
    project = Project.find(session[:workspace_project_id])

    post project_input_dxf_files_path(project, context: "setup"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }

    project.reload
    cut = project.project_layers.find_by!(layer_name: "PIECES")
    ProjectLayer::SetPrimary.call(cut)
    project.update!(status: :ready)
    Workspace.bind!(session, project)
    project
  end

  it "persists clearing an auxiliary layer from Detalle DXF" do
    project = ready_workspace_project!
    attachment = project.input_dxf_attachments.first!
    cut = project.project_layers.find_by!(
      layer_name: "PIECES",
      active_storage_attachment_id: attachment.id
    )
    gravado = project.project_layers.create!(
      layer_name: "GRABADO",
      active_storage_attachment_id: attachment.id,
      included: false
    )

    patch workspace_project_path(project),
          params: {
            section: "layers",
            project_layers: {
              attachment.id.to_s => {
                primary_layer_id: cut.id.to_s,
                gravado.id.to_s => { auxiliary: "1" }
              }
            }
          },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(gravado.reload).to have_attributes(layer_role: "auxiliary", included: true)

    patch workspace_project_path(project),
          params: {
            section: "layers",
            project_layers: {
              attachment.id.to_s => {
                primary_layer_id: cut.id.to_s
              }
            }
          },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(gravado.reload).to have_attributes(layer_role: nil, included: false)
    expect(cut.reload).to have_attributes(layer_role: "primary", included: true)
  end
end
