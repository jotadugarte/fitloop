# frozen_string_literal: true

# [REQ-FIT-DOM-001] DXF layer included in nesting for a project.
# [REQ-FIT-DXF-002] Optional primary / auxiliary role per attachment.
class ProjectLayer < ApplicationRecord
  belongs_to :project, inverse_of: :project_layers

  enum :layer_role, {
    primary: "primary",
    auxiliary: "auxiliary"
  }, validate: { allow_nil: true }

  validates :layer_name, presence: true
  validates :layer_name, uniqueness: { scope: %i[project_id active_storage_attachment_id] }
  validate :only_one_primary_per_attachment, if: -> { layer_role == "primary" }

  def self.set_primary!(layer)
    SetPrimary.call(layer)
  end

  # [REQ-FIT-DXF-002] Marking/auxiliary layers use decoration rules, not closed-contour gaps.
  def closed_contour_gap_validation?
    return false if auxiliary?

    primary? || (layer_role.nil? && included?)
  end

  private

  def only_one_primary_per_attachment
    return if active_storage_attachment_id.blank?

    scope = project.project_layers.where(
      active_storage_attachment_id: active_storage_attachment_id,
      layer_role: :primary
    )
    scope = scope.where.not(id: id) if persisted?

    return unless scope.exists?

    errors.add(:layer_role, :taken)
  end
end
