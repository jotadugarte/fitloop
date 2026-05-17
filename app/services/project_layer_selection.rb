# frozen_string_literal: true

# Applies layer checkbox params from the setup form (grouped by attachment id).
class ProjectLayerSelection
  def self.apply!(project:, raw_params:)
    new(project: project, raw_params: raw_params).apply!
  end

  def initialize(project:, raw_params:)
    @project = project
    @raw_params = raw_params || {}
  end

  def apply!
    permitted = @raw_params.respond_to?(:permit!) ? @raw_params.permit!.to_h : @raw_params.to_h
    return if permitted.blank?

    @project.project_layers.find_each do |layer|
      attachment_key = layer.active_storage_attachment_id&.to_s
      next if attachment_key.blank?

      layer_params = permitted.dig(attachment_key, layer.id.to_s)
      next if layer_params.blank?

      included = layer_params[:included] == "1" || layer_params["included"] == "1"
      layer.update!(included: included)
    end
  end
end
