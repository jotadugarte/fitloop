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
      primary_id = attrs["primary_layer_id"].presence
      auxiliary_ids = auxiliary_layer_ids_from(attrs)

      if primary_id.present?
        apply_primary!(attachment_key, primary_id)
      else
        clear_primaries_on_attachment!(attachment_key)
      end

      layers_on_attachment(attachment_key).find_each do |layer|
        layer_id = layer.id.to_s
        layer_params = attrs[layer_id]

        if layer_params.is_a?(Hash)
          auto_close = layer_params["auto_close_gaps"] == "1"
          layer.update!(auto_close_gaps: auto_close)
        else
          layer.update!(auto_close_gaps: false)
        end

        next if layer_id == primary_id.to_s

        if auxiliary_ids.include?(layer_id)
          layer.update!(layer_role: :auxiliary, included: true)
          Dxf::LayerGapScanner.clear!(layer)
        else
          layer.update!(layer_role: nil, included: false)
          Dxf::LayerGapScanner.clear!(layer)
        end
      end
    end
  end

  def auxiliary_layer_ids_from(attrs)
    attrs.each_with_object([]) do |(layer_key, layer_params), ids|
      next if layer_key == "primary_layer_id"
      next unless layer_params.is_a?(Hash)

      ids << layer_key.to_s if layer_params.stringify_keys["auxiliary"] == "1"
    end
  end

  def layers_on_attachment(attachment_key)
    @project.project_layers.where(active_storage_attachment_id: attachment_key)
  end

  def clear_primaries_on_attachment!(attachment_key)
    layers_on_attachment(attachment_key).where(layer_role: :primary).find_each do |layer|
      layer.update!(layer_role: nil, included: false)
    end
  end

  def apply_flat!(permitted)
    @project.project_layers.find_each do |layer|
      attrs = permitted[layer.id.to_s]
      next if attrs.blank?

      included = attrs[:included] == "1" || attrs["included"] == "1"
      auto_close = attrs[:auto_close_gaps] == "1" || attrs["auto_close_gaps"] == "1"
      layer.update!(included: included, auto_close_gaps: auto_close)
      if included && layer.layer_role.nil?
        Dxf::LayerGapScanner.refresh!(layer.reload)
      elsif !included
        Dxf::LayerGapScanner.clear!(layer)
      end
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
