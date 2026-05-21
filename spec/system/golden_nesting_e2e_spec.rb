# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Golden DXF nesting E2E", type: :system do
  around do |example|
    GoldenFixtures.assert_present!
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  it "[REQ-FIT-QA-001] nests the golden DXF and exposes download + SVG preview" do
    project = create_project_for_spec!(title: "Golden E2E bench", sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
    project.input_dxf.attach(
      io: File.open(GoldenFixtures::GOLDEN_DXF),
      filename: "golden_piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)

    visit project_path(project)
    click_button I18n.t("nesting.start")

    expect(page).to have_css('[data-testid="nesting-result"]')
    expect(page).to have_css('[data-testid="progress-message"]', text: I18n.t("nesting.completed"))
    expect(page).to have_css('[data-testid="download-nested-dxf"]')
    expect(page).to have_css('[data-testid="nesting-preview-svg"]')
    expect(page).to have_css('[data-testid="preview-sheet"]', minimum: 1)

    project.reload
    expect(project.nested_dxf).to be_attached
    expect(project.placements_json).to be_attached
    expect(project.status).to eq("completed")
  end
end
