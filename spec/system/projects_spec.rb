# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project sheet inventory UI", type: :system do
  it "[REQ-FIT-UI-001] shows sheet inventory list on edit" do
    project = Project.create!(
      title: "Sort test",
      pin: "111222",
      sheet_stocks_attributes: {
        "0" => { width_mm: 100, height_mm: 200, quantity: 1, sort_order: 0, limited_quantity: "1" }
      }
    )

    unlock_project_for_spec!(project, pin: "111222")
    visit edit_project_path(project)

    expect(page).to have_css("[data-sheet-inventory]")
    expect(page).to have_css("[data-testid='sheet-stock-row']", count: 1)
    expect(page).to have_button(I18n.t("projects.form.add_sheet"))
    expect(page).to have_button(I18n.t("projects.form.edit_sheet"))
    expect(page).to have_button(I18n.t("projects.form.delete_sheet"))
  end
end
