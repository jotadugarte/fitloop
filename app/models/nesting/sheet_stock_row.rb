# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-002] One sheet stock row for CLI config.json payload.
  class SheetStockRow
    attr_reader :width_mm, :height_mm, :quantity, :sort_order

    def self.from_sheet_stock(stock)
      new(
        width_mm: stock.width_mm,
        height_mm: stock.height_mm,
        quantity: stock.quantity,
        sort_order: stock.sort_order
      )
    end

    def initialize(width_mm:, height_mm:, quantity:, sort_order:)
      @width_mm = Float(width_mm)
      @height_mm = Float(height_mm)
      @quantity = quantity.nil? ? nil : Integer(quantity)
      @sort_order = Integer(sort_order)

      raise ArgumentError, "width_mm must be positive" unless @width_mm.positive?
      raise ArgumentError, "height_mm must be positive" unless @height_mm.positive?
      raise ArgumentError, "quantity must be nil or at least 1" if @quantity && @quantity < 1
      raise ArgumentError, "sort_order must be non-negative" if @sort_order.negative?
    end

    def to_config_hash
      {
        width_mm: @width_mm,
        height_mm: @height_mm,
        quantity: @quantity,
        sort_order: @sort_order
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.width_mm == @width_mm &&
        other.height_mm == @height_mm &&
        other.quantity == @quantity &&
        other.sort_order == @sort_order
    end

    alias eql? ==

    def hash
      [@width_mm, @height_mm, @quantity, @sort_order].hash
    end
  end
end
