# frozen_string_literal: true

require "rails_helper"

RSpec.describe SheetStock, type: :model do
  subject(:sheet_stock) { described_class.new(width_mm: 1000, height_mm: 2000, sort_order: 1) }

  describe "associations [REQ-FIT-DOM-001]" do
    it "[REQ-FIT-DOM-001] belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end
  end

  describe "sheet inventory [REQ-FIT-DOM-001]" do
    it "[REQ-FIT-DOM-001] allows null quantity for infinite sheets" do
      sheet_stock.quantity = nil
      expect(sheet_stock.quantity).to be_nil
    end

    it "[REQ-FIT-DOM-001] persists finite quantity" do
      sheet_stock.quantity = 3
      expect(sheet_stock.quantity).to eq(3)
    end
  end

  describe "unlimited stock cap per project [REQ-FIT-DOM-001]" do
    it "[REQ-FIT-DOM-001] rejects a second unlimited stock on the same project" do
      project = Project.create!(
        title: "Inventory cap",
        pin: "123456",
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: nil, sort_order: 0 }
        }
      )

      project.sheet_stocks.build(
        width_mm: 1200,
        height_mm: 2400,
        quantity: nil,
        sort_order: 1
      )

      expect(project).not_to be_valid
      expect(project.errors).to be_of_kind(:base, :multiple_unlimited_sheet_stocks)
    end
  end
end
