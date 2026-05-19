# frozen_string_literal: true

# [REQ-FIT-SPLIT-001] Child piece geometry produced by an accepted system split.
class DerivedPiece < ApplicationRecord
  belongs_to :project, inverse_of: :derived_pieces

  validates :parent_piece_key, :label, presence: true
  validates :sort_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
