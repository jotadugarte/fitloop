# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project sheet inventory UI", type: :system do
  it "[REQ-FIT-UI-001] shows sheet inventory list on edit" do
    project = create_project_for_spec!(title: "Sort test", sheet_stocks_attributes: {
        "0" => { width_mm: 100, height_mm: 200, quantity: 1, sort_order: 0 }
      }
    )

    visit project_path(project)

    expect(page).to have_css("[data-controller='sheet-inventory']")
    expect(page).to have_css(".sheet-inventory-table")
    expect(page).to have_css("[data-testid='sheet-stock-row']", count: 1)
    expect(page).to have_content("100")
    expect(page).to have_content("200")
    expect(page).to have_button(I18n.t("projects.form.add_sheet"))
    expect(page).to have_button(I18n.t("projects.form.edit_sheet"))
    expect(page).to have_button(I18n.t("projects.form.delete_sheet"))
  end
end
