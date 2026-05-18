# frozen_string_literal: true

require "rails_helper"

RSpec.describe SheetStocks::SyncInventory do
  let(:project) do
    Project.create!(
      ephemeral: true,
      status: :ready,
      title: "Sync inventory",
      kerf_mm: 0,
      margin_mm: 5,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 },
        "1" => { width_mm: 1000, height_mm: 1000, quantity: 10, sort_order: 1 }
      }
    )
  end

  it "[REQ-FIT-DOM-001] destroys sheet stocks omitted from nested attributes" do
    keep = project.sheet_stocks.find_by!(height_mm: 1000, quantity: 10)

    described_class.call(
      project: project,
      sheet_stocks_attributes: {
        "0" => {
          "id" => keep.id,
          "width_mm" => keep.width_mm,
          "height_mm" => keep.height_mm,
          "quantity" => keep.quantity,
          "sort_order" => 0,
          "_destroy" => "0"
        }
      }
    )

    project.reload
    expect(project.sheet_stocks).to contain_exactly(keep)
  end

  it "clears nesting outputs when orphan stocks are removed" do
    keep = project.sheet_stocks.find_by!(height_mm: 1000, quantity: 10)
    project.placements_json.attach(
      io: StringIO.new('{"sheets":[]}'),
      filename: "placements.json",
      content_type: "application/json"
    )
    project.update!(status: :completed)

    described_class.call(
      project: project,
      sheet_stocks_attributes: {
        "0" => { "id" => keep.id, "_destroy" => "0" }
      }
    )

    project.reload
    expect(project.placements_json).not_to be_attached
    expect(project).to be_ready
  end
end
