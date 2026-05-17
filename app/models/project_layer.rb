# frozen_string_literal: true

# [REQ-FIT-DOM-001] DXF layer included in nesting for a project.
class ProjectLayer < ApplicationRecord
  belongs_to :project, inverse_of: :project_layers

  validates :layer_name, presence: true
  validates :layer_name, uniqueness: { scope: %i[project_id active_storage_attachment_id] }
end
