# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Composite DXF layers nesting", type: :system do
  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  let(:composite_fixture) { Rails.root.join("nesting_engine/tests/fixtures/composite-nest-smoke.dxf") }

  it "[REQ-FIT-DXF-002] [REQ-FIT-UI-001] nests with primary and auxiliary layers and preserves layer names in nested DXF" do
    project = create_project_for_spec!(title: "Composite layers bench", sheet_stocks_attributes: {
        "0" => { width_mm: 250, height_mm: 120, quantity: 1, sort_order: 0 }
      }
    )
    project.input_dxf.attach(
      io: File.open(composite_fixture),
      filename: "composite-nest-smoke.dxf",
      content_type: "application/dxf"
    )
    Dxf::LayerSyncPerFile.call(project)
    attachment = project.input_dxf_attachments.first!
    cut = project.project_layers.find_by!(
      layer_name: "CORTE",
      active_storage_attachment_id: attachment.id
    )
    grabado = project.project_layers.find_by!(
      layer_name: "GRABADO",
      active_storage_attachment_id: attachment.id
    )

    visit project_layers_path(project)
    expect(page).to have_css('[data-testid="primary-layer-radio"]')
    choose("primary_layer_#{attachment.id}_#{cut.id}")
    check("project_layers[#{attachment.id}][#{grabado.id}][auxiliary]")
    click_button I18n.t("project_layers.index.save")

    expect(page).to have_current_path(project_path(project))
    expect(cut.reload).to have_attributes(layer_role: "primary", included: true)
    expect(grabado.reload).to have_attributes(layer_role: "auxiliary", included: true)

    expect(page).to have_css('[data-testid="nesting-result"]')
    expect(page).to have_css('[data-testid="progress-message"]', text: I18n.t("nesting.completed"))
    expect(page).to have_css('[data-testid="download-nested-dxf"]')

    project.reload
    expect(project.status).to eq("completed")
    expect(project.nested_dxf).to be_attached

    nested_body = project.nested_dxf.download
    expect(nested_body).to include("CORTE")
    expect(nested_body).to include("GRABADO")
    expect(nested_body).to include("SHEETS")
    expect(nested_body).not_to include("PIECES")
  end
end
