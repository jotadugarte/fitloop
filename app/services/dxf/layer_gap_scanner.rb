# frozen_string_literal: true

module Dxf
  # [REQ-FIT-DXF-002] Scans closed-contour gaps only for primary or legacy included cut layers.
  class LayerGapScanner
    def self.refresh!(layer)
      new(layer).refresh!
    end

    def self.clear!(layer)
      return if layer.gaps_detected.blank?

      layer.update!(gaps_detected: [])
    end

    def initialize(layer)
      @layer = layer
    end

    def refresh!
      return clear! unless @layer.closed_contour_gap_validation?

      attachment = attachment_for_layer
      return clear! if attachment.blank?

      with_downloaded_path(attachment) do |path|
        gaps = gaps_for_layer(path)
        @layer.update!(gaps_detected: gaps)
      end
    end

    def clear!
      self.class.clear!(@layer)
    end

    def gaps_for_layer(path)
      if @layer.primary?
        auxiliary_layers = @layer.project.project_layers
          .where(
            active_storage_attachment_id: @layer.active_storage_attachment_id,
            layer_role: :auxiliary,
            included: true
          )
          .order(:layer_name)
          .pluck(:layer_name)
        LayerNamesReader.gaps_for_composite(
          path: path,
          primary_layer: @layer.layer_name,
          auxiliary_layers: auxiliary_layers,
          auto_close_gaps: @layer.auto_close_gaps?
        )
      else
        LayerNamesReader.gaps_for(path: path, layer_name: @layer.layer_name)
      end
    end

    private

    def attachment_for_layer
      attachment_id = @layer.active_storage_attachment_id
      return if attachment_id.blank?

      @layer.project.input_dxf_attachments.find_by(id: attachment_id)
    end

    def with_downloaded_path(attachment)
      tempfile = Tempfile.new([ "fitloop_dxf_gaps", ".dxf" ], Dir.tmpdir)
      tempfile.binmode
      attachment.download { |chunk| tempfile.write(chunk) }
      tempfile.flush
      yield tempfile.path
    ensure
      tempfile&.close
      tempfile&.unlink
    end
  end
end
