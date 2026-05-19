# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ConfigBuilder do
  it "[REQ-FIT-NEST-002] passes all persisted sheet stocks to the CLI in consumption order" do
    project = Project.create!(
      ephemeral: true,
      status: :ready,
      title: "Config builder",
      kerf_mm: 0,
      margin_mm: 5,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 },
        "1" => { width_mm: 1000, height_mm: 1000, quantity: 10, sort_order: 1 }
      }
    )

    payload = described_class.build(
      project: project,
      work_dir: Rails.root.join("tmp/test_config_builder"),
      input_paths: []
    )

    expect(payload.fetch(:sheet_stocks).size).to eq(2)
    expect(payload.fetch(:sheet_stocks).first).to include(
      width_mm: 1000.0,
      height_mm: 2000.0,
      quantity: 1,
      sort_order: 0
    )
    expect(payload.fetch(:sheet_stocks).last).to include(
      width_mm: 1000.0,
      height_mm: 1000.0,
      quantity: 10,
      sort_order: 1
    )
  end
end
