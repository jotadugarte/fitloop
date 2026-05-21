# frozen_string_literal: true

# [REQ-FIT-SPLIT-001] Draft or accepted split preview for an orphan resolution.
class SplitProposal < ApplicationRecord
  belongs_to :orphan_resolution, inverse_of: :split_proposals

  enum :status, {
    draft: "draft",
    accepted: "accepted",
    rejected: "rejected"
  }, default: :draft, validate: true

  validates :version, numericality: { only_integer: true, greater_than: 0 }

  # [REQ-FIT-SPLIT-001] Engine could not produce a straight-cut split for this piece.
  def split_not_feasible?
    !feasible && plan_reason == "split_not_feasible"
  end
end
