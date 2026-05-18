# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Sheet inventory consumption priority", type: :system do
  it "[REQ-FIT-UI-001] shows priority column header and consumption legend in English" do
    project = create_project_for_spec!(
      title: "Priority UI",
      pin: "111222",
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )

    unlock_project_for_spec!(project, pin: "111222")
    visit edit_project_path(project)

    expect(page).to have_css("[data-controller='sheet-inventory']")
    expect(page).to have_content(I18n.t("projects.form.consumption_priority"))
    expect(page).to have_content(I18n.t("projects.form.consumption_order_legend"))
    expect(page).to have_css("[data-testid='sheet-stock-priority']", count: 1)
  end
end
