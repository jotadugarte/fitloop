# frozen_string_literal: true

module Dxf
  # Persists layer names per input DXF attachment.
  class LayerSyncPerFile
    def self.call(project)
      new(project).call
    end

    def initialize(project)
      @project = project
    end

    def call
      return if @project.input_dxf_attachments.blank?

      attachment_ids = []

      @project.input_dxf_attachments.each do |attachment|
        attachment_ids << attachment.id
        sync_attachment!(attachment)
      end

      stale = @project.project_layers.where.not(active_storage_attachment_id: attachment_ids)
      stale.destroy_all
    end

    private

    def sync_attachment!(attachment)
      with_downloaded_path(attachment) do |path|
        LayerNamesReader.catalog([path]).each do |entry|
          layer = @project.project_layers.find_or_initialize_by(
            active_storage_attachment_id: attachment.id,
            layer_name: entry["name"]
          )
          layer.color = entry["color"] if entry["color"].present?
          layer.included = false if layer.new_record?
          layer.save!
        end
      end
    end

    def with_downloaded_path(attachment)
      tempfile = Tempfile.new([ "fitloop_dxf", ".dxf" ], Dir.tmpdir)
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
