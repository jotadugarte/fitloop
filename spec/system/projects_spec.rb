# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project CRUD", type: :system do
  def add_sheet_from_composer(width:, height:, limited: false, quantity: nil)
    within(".sheet-inventory__composer") do
      fill_in SheetStock.human_attribute_name(:width_mm), with: width.to_s
      fill_in SheetStock.human_attribute_name(:height_mm), with: height.to_s
      if limited
        check SheetStock.human_attribute_name(:limited_quantity)
        fill_in SheetStock.human_attribute_name(:quantity), with: quantity.to_s
      end
      find("[data-testid='sheet-inventory-add']").click
    end
  end

  it "[REQ-FIT-UI-001] creates a project with ordered finite and infinite sheet stocks" do
    visit new_project_path

    fill_in Project.human_attribute_name(:title), with: "Bench project"
    fill_in Project.human_attribute_name(:pin), with: "778899"

    add_sheet_from_composer(width: 1000, height: 2000, limited: true, quantity: 5)
    add_sheet_from_composer(width: 500, height: 300, limited: false)

    click_button I18n.t("projects.form.save_project")

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

  it "[REQ-FIT-UI-001] shows sheet inventory list on edit" do
    project = Project.create!(title: "Sort test", pin: "111222")
    project.sheet_stocks.create!(width_mm: 100, height_mm: 200, quantity: 1, sort_order: 0)

    unlock_project_for_spec!(project, pin: "111222")
    visit edit_project_path(project)

    expect(page).to have_css("[data-sheet-inventory]")
    expect(page).to have_css("[data-testid='sheet-stock-row']", count: 1)
  end
end
