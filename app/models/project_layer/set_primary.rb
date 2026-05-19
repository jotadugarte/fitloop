# frozen_string_literal: true

class ProjectLayer
  # [REQ-FIT-DXF-002] Exclusive primary layer per DXF attachment; primary implies included.
  class SetPrimary
    MAX_SIBLING_CLEAR = 64

    def self.call(layer)
      new(layer).call
    end

    def initialize(layer)
      @layer = layer
    end

    def call
      raise ArgumentError, "layer must be persisted" unless @layer.persisted?
      raise ArgumentError, "attachment required" if @layer.active_storage_attachment_id.blank?

      ApplicationRecord.transaction do
        clear_sibling_primaries!
        @layer.update!(layer_role: :primary, included: true)
        raise "post-condition failed: layer_role primary" unless @layer.layer_role == "primary"
        raise "post-condition failed: included" unless @layer.included?
      end

      @layer
    end

    private

    def clear_sibling_primaries!
      siblings = @layer.project.project_layers.where(
        active_storage_attachment_id: @layer.active_storage_attachment_id,
        layer_role: :primary
      )
      siblings = siblings.where.not(id: @layer.id)

      cleared = 0
      siblings.find_each do |sibling|
        cleared += 1
        raise "sibling clear bound exceeded" if cleared > MAX_SIBLING_CLEAR

        sibling.update!(layer_role: nil)
      end
    end
  end
end
