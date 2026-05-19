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

  it "[REQ-FIT-UI-001] shows finite then unlimited rows with matching priority labels" do
    project = create_project_for_spec!(
      title: "Finite then unlimited",
      pin: "333444",
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 },
        "1" => { width_mm: 2500, height_mm: 3500, quantity: nil, sort_order: 1 }
      }
    )

    unlock_project_for_spec!(project, pin: "333444")
    visit edit_project_path(project)

    rows = page.all("[data-testid='sheet-stock-row']")
    expect(rows.size).to eq(2)
    expect(rows.first).to have_css("[data-testid='sheet-stock-priority']", text: "#1")
    expect(rows.first).to have_content("1000")
    expect(rows.last).to have_css("[data-testid='sheet-stock-priority']", text: "#2")
    expect(rows.last).to have_content(I18n.t("projects.form.quantity_unlimited"))
  end

  it "[REQ-FIT-UI-001] exposes drag handles for reordering sheet rows" do
    project = create_project_for_spec!(
      title: "Reorder handles",
      pin: "555666",
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 },
        "1" => { width_mm: 2500, height_mm: 3500, quantity: nil, sort_order: 1 }
      }
    )

    unlock_project_for_spec!(project, pin: "555666")
    visit edit_project_path(project)

    expect(page).to have_css("[data-testid='sheet-stock-drag-handle']", count: 2)
    expect(page).to have_css("[data-sheet-inventory-target='list'][data-sortable='true']")
  end

  it "[REQ-FIT-UI-001] keeps quantity enabled when an unlimited stock already exists" do
    project = create_project_for_spec!(
      title: "Unlimited cap UI",
      pin: "999000",
      sheet_stocks_attributes: {
        "0" => { width_mm: 2500, height_mm: 3500, quantity: nil, sort_order: 0 }
      }
    )

    unlock_project_for_spec!(project, pin: "999000")
    visit edit_project_path(project)

    expect(page).to have_css("[data-controller='sheet-inventory'][data-sheet-inventory-has-unlimited-value='true']")
    expect(page).to have_field("sheet_composer_quantity", disabled: false)
    expect(page).to have_css(".sheet-inventory__legend", text: I18n.t("projects.form.consumption_order_legend"))
  end
end
