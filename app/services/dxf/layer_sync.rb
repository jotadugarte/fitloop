# frozen_string_literal: true

module Dxf
  # [REQ-FIT-DXF-001] Persists unioned layer names and colors from attached input DXFs.
  class LayerSync
    def self.call(project)
      new(project).call
    end

    def initialize(project)
      @project = project
    end

    def call
      if @project.input_dxf_attachments.blank?
        @project.project_layers.destroy_all
        return
      end

      active_names = []
      with_downloaded_dxf_paths do |paths|
        LayerNamesReader.catalog(paths).each do |entry|
          name = entry["name"]
          active_names << name
          layer = @project.project_layers.find_or_initialize_by(
            layer_name: name,
            active_storage_attachment_id: nil
          )
          layer.color = entry["color"] if entry["color"].present?
          layer.save!
        end
      end

      stale = @project.project_layers.where.not(active_storage_attachment_id: nil)
                                     .or(@project.project_layers.where.not(layer_name: active_names))
      stale.destroy_all
    end

    private

    def with_downloaded_dxf_paths
      tempfiles = []
      paths = @project.input_dxf_attachments.map do |attachment|
        tempfile = Tempfile.new([ "fitloop_dxf", ".dxf" ], Dir.tmpdir)
        tempfiles << tempfile
        tempfile.binmode
        attachment.download { |chunk| tempfile.write(chunk) }
        tempfile.flush
        tempfile.path
      end
      yield paths
    ensure
      (tempfiles || []).each do |tempfile|
        tempfile.close
        tempfile.unlink
      end
    end
  end
end
