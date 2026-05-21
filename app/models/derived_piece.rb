# frozen_string_literal: true

# [REQ-FIT-SPLIT-001] Child piece geometry produced by an accepted system split.
class DerivedPiece < ApplicationRecord
  belongs_to :project, inverse_of: :derived_pieces

  validates :parent_piece_key, :label, presence: true
  validates :sort_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Suffix letter from labels like Pieza-1a (storage) for display as A, B, …
  def display_suffix
    match = label.to_s.match(/\APieza-\d+(.*)\z/i)
    raw = match&.[](1).presence || label.to_s
    raw.upcase
  end

  def bounding_width_mm
    bounding_box_mm[:width_mm]
  end

  def bounding_height_mm
    bounding_box_mm[:height_mm]
  end

  def bounding_box_mm
    rings = Array(geometry_json&.fetch("rings", nil))
    points = rings.flat_map { |ring| Array(ring) }
    return { width_mm: 0.0, height_mm: 0.0 } if points.empty?

    xs = points.map { |point| point.fetch(0).to_f }
    ys = points.map { |point| point.fetch(1).to_f }
    {
      width_mm: xs.max - xs.min,
      height_mm: ys.max - ys.min
    }
  end
end
