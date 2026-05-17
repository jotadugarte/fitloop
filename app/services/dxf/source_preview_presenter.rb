# frozen_string_literal: true

module Dxf
  # [REQ-FIT-UI-002] Original DXF preview for layers selected for nesting.
  class SourcePreviewPresenter
    Layer = Struct.new(:name, :color, :polylines, keyword_init: true)

    def self.for(project)
      new(project: project)
    end

    def initialize(project:)
      @project = project
      @data = load_data
    end

    def available?
      layers.any? { |layer| layer.polylines.any? }
    end

    def layers
      @layers ||= build_layers
    end

    def view_width
      @data.fetch("width_mm").to_f
    end

    def view_height
      @data.fetch("height_mm").to_f
    end

    def offset_x_mm
      @data.fetch("offset_x_mm").to_f
    end

    def offset_y_mm
      @data.fetch("offset_y_mm").to_f
    end

    def view_box
      "0 0 #{view_width} #{view_height}"
    end

    def included_layer_names
      @included_layer_names ||= @project.project_layers.where(included: true).order(:layer_name).pluck(:layer_name)
    end

    private

    def load_data
      return SourcePreviewReader.empty_payload if @project.input_dxf_attachments.blank?
      return SourcePreviewReader.empty_payload if included_layer_names.blank?

      with_downloaded_dxf_paths do |paths|
        SourcePreviewReader.preview(
          paths: paths,
          layer_names: included_layer_names,
          curve_tolerance_mm: @project.curve_tolerance_mm
        )
      end
    rescue SourcePreviewReader::Error
      SourcePreviewReader.empty_payload
    end

    def build_layers
      Array(@data["layers"]).map do |row|
        Layer.new(
          name: row.fetch("name"),
          color: row.fetch("color"),
          polylines: normalize_polylines(row["polylines"])
        )
      end
    end

    def normalize_polylines(polylines)
      Array(polylines).map do |line|
        Array(line).map { |point| [ point.fetch(0).to_f, point.fetch(1).to_f ] }
      end
    end

    def with_downloaded_dxf_paths
      tempfiles = []
      paths = @project.input_dxf_attachments.map do |attachment|
        tempfile = Tempfile.new([ "fitloop_dxf_preview", ".dxf" ], Dir.tmpdir)
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
