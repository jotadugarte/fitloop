# frozen_string_literal: true

# Applies layer params from setup or layers forms (flat or grouped by attachment id).
# [REQ-FIT-DXF-001] included checkboxes; [REQ-FIT-DXF-002] primary + auxiliary per file.
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

    if grouped_by_attachment?(permitted)
      apply_grouped!(permitted)
    else
      apply_flat!(permitted)
    end
  end

  private

  def grouped_by_attachment?(permitted)
    permitted.keys.all? { |key| attachment_id?(key) }
  end

  def attachment_id?(key)
    @project.input_dxf_attachments.exists?(id: key)
  end

  def apply_grouped!(permitted)
    permitted.each do |attachment_key, attachment_params|
      next unless attachment_params.is_a?(Hash)

      attrs = attachment_params.stringify_keys
      primary_id = attrs["primary_layer_id"]

      attrs.each do |layer_key, layer_params|
        next if layer_key == "primary_layer_id"
        next unless layer_params.is_a?(Hash)

        layer = find_layer(attachment_key, layer_key)
        next unless layer

        apply_layer_role_attrs!(layer, layer_params)
      end

      apply_primary!(attachment_key, primary_id) if primary_id.present?
    end
  end

  def apply_flat!(permitted)
    @project.project_layers.find_each do |layer|
      attrs = permitted[layer.id.to_s]
      next if attrs.blank?

      included = attrs[:included] == "1" || attrs["included"] == "1"
      layer.update!(included: included)
    end
  end

  def find_layer(attachment_key, layer_key)
    @project.project_layers.find_by(
      id: layer_key,
      active_storage_attachment_id: attachment_key
    )
  end

  def apply_layer_role_attrs!(layer, layer_params)
    params = layer_params.stringify_keys

    if params["auxiliary"] == "1"
      layer.update!(layer_role: :auxiliary, included: true)
      return
    end

    return unless params.key?("included")

    included = params["included"] == "1"
    if included
      layer.update!(included: true, layer_role: nil) unless layer.layer_role == "primary"
    else
      layer.update!(included: false, layer_role: nil) unless layer.layer_role == "primary"
    end
  end

  def apply_primary!(attachment_key, primary_id)
    layer = @project.project_layers.find_by(
      id: primary_id,
      active_storage_attachment_id: attachment_key
    )
    raise ArgumentError, "primary layer not found" unless layer

    ProjectLayer::SetPrimary.call(layer)
  end
end
