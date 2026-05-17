# frozen_string_literal: true

module Dxf
  # [REQ-FIT-DXF-001] Persists unioned layer names from attached input DXFs.
  class LayerSync
    def self.call(project)
      new(project).call
    end

    def initialize(project)
      @project = project
    end

    def call
      return if @project.input_dxf_attachments.blank?

      with_downloaded_dxf_paths do |paths|
        LayerNamesReader.union(paths).each do |layer_name|
          @project.project_layers.find_or_create_by!(layer_name: layer_name)
        end
      end
    end

    private

    def with_downloaded_dxf_paths
      tempfiles = []
      paths = @project.input_dxf_attachments.map do |attachment|
        tempfile = Tempfile.new(["fitloop_dxf", ".dxf"], Dir.tmpdir)
        tempfiles << tempfile
        tempfile.binmode
        attachment.download { |chunk| tempfile.write(chunk) }
        tempfile.flush
        tempfile.path
      end
      yield paths
    ensure
      tempfiles&.each do |tempfile|
        tempfile.close
        tempfile.unlink
      end
    end
  end
end
