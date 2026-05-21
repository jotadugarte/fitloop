# frozen_string_literal: true

# [REQ-FIT-SPLIT-001] Per-piece orphan resolution state for auto-split workflow.
class OrphanResolution < ApplicationRecord
  belongs_to :project, inverse_of: :orphan_resolutions
  belongs_to :last_nesting_run, class_name: "NestingRun", optional: true, inverse_of: :orphan_resolutions
  has_many :split_proposals, dependent: :destroy, inverse_of: :orphan_resolution

  enum :resolution_state, {
    pending: "pending",
    system_split: "system_split",
    manual: "manual",
    resolved: "resolved"
  }, default: :pending, validate: true

  validates :piece_key, presence: true, uniqueness: { scope: :project_id }
  validates :reason, presence: true, on: :create
end
