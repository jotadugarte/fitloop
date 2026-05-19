# frozen_string_literal: true

module Dxf
  # [REQ-FIT-UI-002] Original DXF preview for layers selected for nesting.
  class SourcePreviewPresenter
    Layer = Struct.new(:name, :color, :polylines, keyword_init: true)

    def self.for(project, attachment: nil)
      new(project: project, attachment: attachment)
    end

    def initialize(project:, attachment: nil)
      @project = project
      @attachment = attachment
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
      @included_layer_names ||= begin
        scope = @project.project_layers.where(included: true)
        scope = scope.where(active_storage_attachment_id: @attachment.id) if @attachment
        scope.order(:layer_name).pluck(:layer_name)
      end
    end

    private

    def load_data
      return SourcePreviewReader.empty_payload if @project.input_dxf_attachments.blank?
      return SourcePreviewReader.empty_payload unless preview_config_ready?

      with_downloaded_dxf_paths do |paths|
        SourcePreviewReader.preview(
          paths: paths,
          curve_tolerance_mm: @project.curve_tolerance_mm,
          **reader_preview_options
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

    def preview_config_ready?
      reader_preview_options.present?
    end

    def reader_preview_options
      if per_file_preview_configs?
        files = preview_input_files
        return {} if files.blank?

        { input_files: files }
      else
        return {} if included_layer_names.blank?

        { layer_names: included_layer_names }
      end
    end

    def per_file_preview_configs?
      composite_preview? ||
        @project.project_layers.where.not(active_storage_attachment_id: nil).exists?
    end

    def composite_preview?
      preview_attachments.any? { |attachment| primary_layer_for(attachment).present? }
    end

    def preview_input_files
      preview_attachments.filter_map do |attachment|
        primary = primary_layer_for(attachment)
        if primary
          entry = { primary_layer: primary.layer_name }
          auxiliary = auxiliary_layers_for(attachment)
          entry[:auxiliary_layers] = auxiliary if auxiliary.any?
          entry
        else
          names = included_layers_for(attachment)
          next if names.blank?

          { layer_names: names }
        end
      end
    end

    def included_layers_for(attachment)
      @project.project_layers
        .where(included: true, active_storage_attachment_id: attachment.id)
        .order(:layer_name)
        .pluck(:layer_name)
    end

    def preview_attachments
      @attachment ? [ @attachment ] : @project.input_dxf_attachments.to_a
    end

    def primary_layer_for(attachment)
      @project.project_layers.find_by(
        active_storage_attachment_id: attachment.id,
        included: true,
        layer_role: :primary
      )
    end

    def auxiliary_layers_for(attachment)
      @project.project_layers
        .where(included: true, active_storage_attachment_id: attachment.id, layer_role: :auxiliary)
        .order(:layer_name)
        .pluck(:layer_name)
    end

    def with_downloaded_dxf_paths
      tempfiles = []
      attachments = @attachment ? [ @attachment ] : @project.input_dxf_attachments.to_a
      paths = attachments.map do |attachment|
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
