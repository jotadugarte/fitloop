# frozen_string_literal: true

module Dxf
  # [REQ-FIT-UI-002] Original DXF preview for layers selected for nesting.
  class SourcePreviewPresenter
    Layer = Struct.new(:name, :color, :polylines, :gaps, :auto_close_lines, :auto_close_gaps, keyword_init: true)

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
        layer_name = row.fetch("name")
        proj_layer = @project.project_layers.find_by(
          layer_name: layer_name,
          active_storage_attachment_id: @attachment&.id
        ) || @project.project_layers.find_by(layer_name: layer_name)

        auto_close = proj_layer&.auto_close_gaps? || false

        Layer.new(
          name: layer_name,
          color: row.fetch("color"),
          polylines: normalize_polylines(row["polylines"]),
          gaps: normalize_gaps(row["gaps"]),
          auto_close_lines: normalize_polylines(row["auto_close_lines"]),
          auto_close_gaps: auto_close
        )
      end
    end

    def normalize_polylines(polylines)
      Array(polylines).map do |line|
        Array(line).map { |point| [ point.fetch(0).to_f, point.fetch(1).to_f ] }
      end
    end

    def normalize_gaps(gaps)
      Array(gaps).map do |gap|
        {
          distance_mm: gap.fetch("distance_mm").to_f,
          start: [ gap.fetch("start").fetch(0).to_f, gap.fetch("start").fetch(1).to_f ],
          end: [ gap.fetch("end").fetch(0).to_f, gap.fetch("end").fetch(1).to_f ],
          auto_closed: !!gap.fetch("auto_closed")
        }
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
          entry[:auto_close_layers] = [primary.layer_name] if primary.auto_close_gaps?
          entry
        else
          names = included_layers_for(attachment)
          next if names.blank?

          auto_closed = @project.project_layers
            .where(active_storage_attachment_id: attachment.id, included: true, auto_close_gaps: true)
            .order(:layer_name)
            .pluck(:layer_name)

          entry = { layer_names: names }
          entry[:auto_close_layers] = auto_closed if auto_closed.any?
          entry
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
