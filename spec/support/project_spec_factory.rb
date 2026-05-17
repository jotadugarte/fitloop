# frozen_string_literal: true

module ProjectSpecFactory
  DEFAULT_SHEET_STOCK = {
    width_mm: 1000,
    height_mm: 2000,
    quantity: 1,
    sort_order: 0,
    limited_quantity: "1"
  }.freeze

  module_function

  def create!(title:, pin:, sheet_stocks_attributes: nil, **attrs)
    Project.create!(
      title: title,
      pin: pin,
      sheet_stocks_attributes: sheet_stocks_attributes || { "0" => DEFAULT_SHEET_STOCK.dup },
      **attrs
    )
  end
end

RSpec.configure do |config|
  config.include(Module.new do
    def create_project_for_spec!(**kwargs)
      ProjectSpecFactory.create!(**kwargs)
    end
  end)
end
