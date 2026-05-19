# frozen_string_literal: true

require "rails_helper"

RSpec.describe SheetStocks::NormalizeConsumptionOrder do
  describe ".call [REQ-FIT-DOM-001]" do
    it "places all finite stocks before the unlimited stock with dense sort_order ranks" do
      project = Project.create!(
        title: "Normalize consumption order",
        pin: "654321",
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: nil, sort_order: 0 },
          "1" => { width_mm: 800, height_mm: 1600, quantity: 5, sort_order: 1 }
        }
      )

      described_class.call(project)
      described_class.persist!(project)
      project.reload

      ordered = project.sheet_stocks.order(:sort_order)
      expect(ordered.map(&:quantity)).to eq([5, nil])
      expect(ordered.map(&:sort_order)).to eq([0, 1])
    end

    it "preserves relative order among multiple finite stocks" do
      project = Project.create!(
        title: "Finite relative order",
        pin: "112233",
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: nil, sort_order: 0 },
          "1" => { width_mm: 900, height_mm: 1800, quantity: 2, sort_order: 2 },
          "2" => { width_mm: 800, height_mm: 1600, quantity: 5, sort_order: 1 }
        }
      )

      described_class.call(project)
      described_class.persist!(project)
      project.reload

      finites = project.sheet_stocks.order(:sort_order).reject { |s| s.quantity.nil? }
      expect(finites.map(&:quantity)).to eq([5, 2])
      expect(project.sheet_stocks.order(:sort_order).last.quantity).to be_nil
    end
  end
end
