# frozen_string_literal: true

module Dxf
  # [REQ-FIT-UI-002] Original DXF preview for layers selected for nesting.
  class SourcePreviewPresenter
    Layer = Struct.new(:name, :color, :polylines, :gaps, :auto_close_lines, :auto_close_gaps, keyword_init: true)
    Polyline = Struct.new(:points, :is_open, keyword_init: true)

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

    def has_open_shapes?
      layers.any? { |layer| layer.polylines.any?(&:is_open) || showable_gaps?(layer) }
    end

    def has_valid_shapes?
      layers.any? { |layer| layer.polylines.any? { |p| !p.is_open } }
    end

    def zoom_to_corrections?
      layers.any?(&:auto_close_gaps)
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

    def corrections_view_box
      min_x = Float::INFINITY
      min_y = Float::INFINITY
      max_x = -Float::INFINITY
      max_y = -Float::INFINITY

      layers.each do |layer|
        layer.gaps.each do |gap|
          [gap[:start], gap[:end]].each do |pt|
            x = pt[0]
            y = pt[1]
            min_x = x if x < min_x
            min_y = y if y < min_y
            max_x = x if x > max_x
            max_y = y if y > max_y
          end
        end
      end

      if min_x == Float::INFINITY
        return view_box
      end

      svg_x1 = min_x - offset_x_mm
      svg_x2 = max_x - offset_x_mm
      svg_y1 = view_height - (max_y - offset_y_mm)
      svg_y2 = view_height - (min_y - offset_y_mm)

      svg_width = svg_x2 - svg_x1
      svg_height = svg_y2 - svg_y1

      padding_x = [svg_width * 0.3, 30.0].max
      padding_y = [svg_height * 0.3, 30.0].max

      zoom_x = svg_x1 - padding_x
      zoom_y = svg_y1 - padding_y
      zoom_w = svg_width + 2 * padding_x
      zoom_h = svg_height + 2 * padding_y

      "#{zoom_x} #{zoom_y} #{zoom_w} #{zoom_h}"
    end

    def included_layer_names
      @included_layer_names ||= begin
        if per_file_preview_configs?
          preview_attachments.flat_map { |attachment| preview_layer_names_for(attachment) }.uniq.sort
        else
          included = @project.project_layers.where(included: true).order(:layer_name).pluck(:layer_name)
          gap_names = @project.project_layers.order(:layer_name).select { |layer|
            layer.closed_contour_gap_validation? && showable_detected_gaps?(layer)
          }.map(&:layer_name)
          (included + gap_names).uniq.sort
        end
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
        auto_close = if @attachment
                       @project.project_layers.find_by(
                         layer_name: layer_name,
                         active_storage_attachment_id: @attachment.id
                       )&.auto_close_gaps? || false
                     else
                       @project.project_layers.where(
                         layer_name: layer_name,
                         included: true,
                         auto_close_gaps: true
                       ).exists?
                     end

        Layer.new(
          name: layer_name,
          color: row.fetch("color"),
          polylines: normalize_polylines(row["polylines"], row["polyline_open_flags"]),
          gaps: merged_gaps_for(layer_name, row["gaps"], auto_close: auto_close),
          auto_close_lines: normalize_raw_polylines(row["auto_close_lines"]),
          auto_close_gaps: auto_close
        )
      end
    end

    def normalize_polylines(polylines, open_flags)
      flags = Array(open_flags)
      Array(polylines).each_with_index.map do |line, index|
        points = Array(line).map { |point| [ point.fetch(0).to_f, point.fetch(1).to_f ] }
        is_open = !!flags[index]
        Polyline.new(points: points, is_open: is_open)
      end
    end

    def normalize_raw_polylines(polylines)
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
          auto_closed: !!gap["auto_closed"]
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
          auxiliary = (auxiliary_layers_for(attachment) + preview_layer_names_for(attachment) - [ primary.layer_name ]).uniq.sort
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
      preview_layer_names_for(attachment)
    end

    def preview_layer_names_for(attachment)
      included = @project.project_layers
        .where(included: true, active_storage_attachment_id: attachment.id)
        .order(:layer_name)
        .pluck(:layer_name)
      (included + gap_layer_names_for(attachment)).uniq.sort
    end

    def gap_layer_names_for(attachment)
      @project.project_layers
        .where(active_storage_attachment_id: attachment.id)
        .order(:layer_name)
        .select { |layer| layer.closed_contour_gap_validation? && showable_detected_gaps?(layer) }
        .map(&:layer_name)
    end

    def merged_gaps_for(layer_name, preview_gaps, auto_close:)
      gaps = normalize_gaps(preview_gaps)
      project_layer = project_layer_for(layer_name)
      return gaps if project_layer.blank?
      return gaps unless project_layer.closed_contour_gap_validation?

      detected = normalize_gaps(project_layer.gaps_detected)
      return gaps if detected.empty?

      merge_gaps(gaps, detected, auto_close: auto_close)
    end

    def merge_gaps(preview_gaps, detected_gaps, auto_close:)
      keys = preview_gaps.map { |gap| gap_key(gap) }
      detected_gaps.each do |gap|
        key = gap_key(gap)
        next if keys.include?(key)

        preview_gaps << gap.merge(auto_closed: auto_close && gap[:distance_mm] <= 15.0)
        keys << key
      end
      preview_gaps
    end

    def gap_key(gap)
      [
        gap[:distance_mm].to_f.round(4),
        gap[:start][0].to_f.round(4),
        gap[:start][1].to_f.round(4),
        gap[:end][0].to_f.round(4),
        gap[:end][1].to_f.round(4)
      ]
    end

    def showable_gaps?(layer)
      layer.gaps.any? { |gap| gap[:distance_mm].to_f > 2.0 && !gap[:auto_closed] }
    end

    def showable_detected_gaps?(layer)
      Nesting::GapReport.from_json(layer.gaps_detected).gaps.any? { |gap| gap.value > 2.0 }
    end

    def project_layer_for(layer_name)
      scope = @project.project_layers.where(layer_name: layer_name)
      scope = scope.where(active_storage_attachment_id: @attachment.id) if @attachment
      scope.first
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
