# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::SheetStockRow, "[REQ-FIT-NEST-002]" do
  let(:project) do
    create_project_for_spec!(
      title: "Sheet stock row",
      bind_workspace: false,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end

  describe ".from_sheet_stock" do
    it "builds from AR and emits legacy config keys" do
      stock = project.sheet_stocks.first!
      row = described_class.from_sheet_stock(stock)

      expect(row.to_config_hash).to eq(
        width_mm: 1000.0,
        height_mm: 2000.0,
        quantity: 1,
        sort_order: 0
      )
    end
  end

  describe "#initialize" do
    it "accepts nil quantity for unlimited stock" do
      row = described_class.new(width_mm: 500, height_mm: 800, quantity: nil, sort_order: 1)

      expect(row.to_config_hash[:quantity]).to be_nil
    end

    it "rejects non-positive dimensions and invalid quantity" do
      expect do
        described_class.new(width_mm: 0, height_mm: 800, quantity: 1, sort_order: 0)
      end.to raise_error(ArgumentError, /width_mm/)

      expect do
        described_class.new(width_mm: 500, height_mm: 800, quantity: 0, sort_order: 0)
      end.to raise_error(ArgumentError, /quantity/)
    end
  end
end
