# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nesting progress UI", type: :system do
  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  it "[REQ-FIT-JOB-001] starts nesting and shows completed progress on the project page" do
    project = create_project_for_spec!(title: "Turbo progress bench", sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)

    visit project_path(project)
    click_button I18n.t("nesting.start")

    expect(page).to have_css('[data-testid="nesting-result"]')
    expect(page).to have_css('[data-testid="progress-message"]', text: I18n.t("nesting.completed"))
    expect(page).to have_css('[data-testid="nesting-preview-svg"]')
    expect(page).to have_css('[data-testid="preview-sheet"]', minimum: 1)
  end
end
