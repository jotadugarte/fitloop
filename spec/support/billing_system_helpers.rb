# frozen_string_literal: true

# [REQ-FIT-BILL-001] System spec helpers for auth + billing flows.
module BillingSystemHelpers
  def setup_golden_nested_project!
    project = create_project_for_spec!(
      title: "2:30 AM bench",
      sheet_stocks_attributes: {
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
    expect(page).to have_css('[data-testid="download-nested-dxf"]')

    project.reload
    expect(project.nested_dxf).to be_attached
    project
  end

  def discard_workshop_session!
    Workspace.discard!(page_session)
  end
end

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :system
  config.include BillingModelHelpers, type: :system
  config.include BillingSystemHelpers, type: :system
end
