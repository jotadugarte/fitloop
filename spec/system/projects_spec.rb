# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project CRUD", type: :system do
  it "[REQ-FIT-UI-001] creates a project with ordered finite and infinite sheet stocks" do
    visit new_project_path

    fill_in "Title", with: "Bench project"
    fill_in "PIN", with: "778899"

    within(first("[data-testid='sheet-stock-row']")) do
      fill_in "Width (mm)", with: "1000"
      fill_in "Height (mm)", with: "2000"
      fill_in "Quantity", with: "5"
    end

    click_button "Add sheet type"

    within(all("[data-testid='sheet-stock-row']").last) do
      fill_in "Width (mm)", with: "500"
      fill_in "Height (mm)", with: "300"
      check "Unlimited quantity"
    end

    click_button "Save project"

    expect(page).to have_content("Bench project")

    project = Project.find_by!(title: "Bench project")
    stocks = project.sheet_stocks.order(:sort_order).to_a

    expect(stocks.size).to eq(2)
    expect(stocks[0].width_mm).to eq(1000)
    expect(stocks[0].quantity).to eq(5)
    expect(stocks[1].width_mm).to eq(500)
    expect(stocks[1].quantity).to be_nil
    expect(stocks.map(&:sort_order)).to eq([ 0, 1 ])
  end

  it "[REQ-FIT-UI-001] shows sortable sheet stock rows on edit" do
    project = Project.create!(title: "Sort test", pin: "111222")
    project.sheet_stocks.create!(width_mm: 100, height_mm: 200, quantity: 1, sort_order: 0)

    unlock_project_for_spec!(project, pin: "111222")
    visit edit_project_path(project)

    expect(page).to have_css("[data-controller~='sortable'][data-sortable-resource='sheet-stock']")
  end
end
