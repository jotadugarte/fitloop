# frozen_string_literal: true

# [REQ-FIT-DOM-001] One nesting execution for a project.
class NestingRun < ApplicationRecord
  belongs_to :project, inverse_of: :nesting_runs

  validates :status, presence: true
end
