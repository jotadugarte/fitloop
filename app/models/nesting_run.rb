# frozen_string_literal: true

# [REQ-FIT-DOM-001] One nesting execution for a project.
class NestingRun < ApplicationRecord
  belongs_to :project, inverse_of: :nesting_runs
  has_many :download_grants, dependent: :nullify
  has_many :payments, dependent: :nullify
  has_many :orphan_resolutions,
           foreign_key: :last_nesting_run_id,
           dependent: :nullify,
           inverse_of: :last_nesting_run

  validates :status, presence: true
end
