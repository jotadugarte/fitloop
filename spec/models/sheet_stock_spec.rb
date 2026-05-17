# frozen_string_literal: true

require "rails_helper"

RSpec.describe SheetStock, type: :model do
  subject(:sheet_stock) { described_class.new(width_mm: 1000, height_mm: 2000, sort_order: 1) }

  describe "associations [REQ-FIT-DOM-001]" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end
  end

  describe "sheet inventory [REQ-FIT-DOM-001]" do
    it "allows null quantity for infinite sheets" do
      sheet_stock.quantity = nil
      expect(sheet_stock.quantity).to be_nil
    end

    it "persists finite quantity" do
      sheet_stock.quantity = 3
      expect(sheet_stock.quantity).to eq(3)
    end
  end
end
