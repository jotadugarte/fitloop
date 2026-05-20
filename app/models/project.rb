# frozen_string_literal: true

# [REQ-FIT-DOM-001] Nesting project with sheet inventory, layers, and job parameters.
# [REQ-FIT-AUTH-001] Ephemeral workspace projects; access via session bind (see ADR-0004).
class Project < ApplicationRecord
  attribute :ephemeral, :boolean, default: true

  scope :ephemeral, -> { where(ephemeral: true) }

  has_many :sheet_stocks, -> { order(:sort_order) }, dependent: :destroy, inverse_of: :project

  accepts_nested_attributes_for :sheet_stocks, allow_destroy: true
  has_many :project_layers, dependent: :destroy, inverse_of: :project
  has_many :nesting_runs, dependent: :destroy, inverse_of: :project
  has_many :orphan_resolutions, dependent: :destroy, inverse_of: :project
  has_many :derived_pieces, dependent: :destroy, inverse_of: :project
  has_many_attached :input_dxf
  has_one_attached :nested_dxf
  has_one_attached :placements_json

  enum :status, {
    draft: "draft",
    ready: "ready",
    processing: "processing",
    completed: "completed",
    partial: "partial",
    failed: "failed"
  }, default: :draft, validate: true

  validates :title, presence: true
  validates :kerf_mm, :margin_mm, :sheet_gap_mm,
            numericality: { greater_than_or_equal_to: 0 }
  validates :curve_tolerance_mm, numericality: { greater_than: 0 }
  validate :must_have_sheet_stocks, unless: :ephemeral?
  validate :at_most_one_unlimited_sheet_stock

  # [REQ-FIT-SPLIT-001] Show dedicated re-nest CTA after accepted splits materialize derived pieces.
  def nest_with_updated_pieces_available?
    derived_pieces.exists? && (completed? || partial?)
  end

  private

  def must_have_sheet_stocks
    return if sheet_stocks.reject(&:marked_for_destruction?).any?

    errors.add(:base, :no_sheet_stocks)
  end

  # [REQ-FIT-DOM-001] At most one SheetStock with quantity nil (∞) per project.
  def at_most_one_unlimited_sheet_stock
    active_stocks = sheet_stocks.reject(&:marked_for_destruction?)
    unlimited_count = active_stocks.count { |stock| stock.quantity.nil? }
    return if unlimited_count <= 1

    errors.add(:base, :multiple_unlimited_sheet_stocks)
  end
end
