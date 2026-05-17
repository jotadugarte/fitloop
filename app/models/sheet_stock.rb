# frozen_string_literal: true

# [REQ-FIT-DOM-001] Ordered sheet type in project inventory (quantity nil = infinite).
class SheetStock < ApplicationRecord
  attr_accessor :unlimited_quantity

  belongs_to :project, inverse_of: :sheet_stocks

  validates :width_mm, :height_mm, :sort_order, presence: true
  validates :width_mm, :height_mm, numericality: { greater_than: 0 }
end
