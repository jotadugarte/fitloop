# frozen_string_literal: true

# [REQ-FIT-NEST-003] SVG preview for orphan pieces.
module OrphansPreviewHelper
  def orphan_preview_svg(orphan, css_class:)
    tag.svg(
      class: css_class,
      viewBox: orphan.view_box,
      xmlns: "http://www.w3.org/2000/svg",
      role: "img",
      aria: { labelledby: orphan_preview_label_id(orphan) },
      data: { testid: "orphan-preview-svg", piece_index: orphan.piece_index }
    ) do
      tag.title(id: orphan_preview_label_id(orphan)) do
        t("nesting.orphan_preview.label", piece_number: orphan.display_number)
      end +
        tag.path(
          d: orphan_preview_path(orphan),
          class: "orphan-preview__piece",
          fill_rule: "evenodd",
          vector_effect: "non-scaling-stroke"
        )
    end
  end

  def split_plan_preview_svg(orphan, css_class:)
    proposal = orphan.split_proposal
    return unless proposal
    return unless proposal.draft? || proposal.accepted?

    geometries = Array(proposal.child_piece_geometries)
    mother_rings = orphan.exportable? ? orphan.rings : []
    bounds = split_preview_bounds(geometries, extra_rings: mother_rings)
    return if bounds.nil?

    minx, miny, maxx, maxy = bounds
    width = (maxx - minx) + (2 * padding)
    height = (maxy - miny) + (2 * padding)
    view_box = "0 0 #{width} #{height}"

    tag.svg(
      class: css_class,
      viewBox: view_box,
      xmlns: "http://www.w3.org/2000/svg",
      role: "img",
      data: { testid: "split-plan-preview-svg", piece_index: orphan.piece_index }
    ) do
      paths = []
      if mother_rings.present?
        paths.concat(
          split_mother_paths(mother_rings, bounds: bounds, padding: padding)
        )
      end
      paths.concat(
        geometries.each_with_index.flat_map do |child, index|
          split_child_paths(child, bounds: bounds, padding: padding, child_index: index)
        end
      )
      paths.concat(split_cut_paths(proposal.cut_segments, bounds: bounds, padding: padding))
      safe_join(paths)
    end
  end

  def orphan_preview_dimensions(orphan)
    preview_dimensions_text(orphan.width_mm, orphan.height_mm)
  end

  def derived_piece_title(piece, parent_display_number:)
    t(
      "nesting.derived_piece.title",
      piece_number: parent_display_number,
      suffix: piece.display_suffix
    )
  end

  def derived_piece_dimensions(piece)
    preview_dimensions_text(piece.bounding_width_mm, piece.bounding_height_mm)
  end

  private

  def preview_dimensions_text(width_mm, height_mm)
    t(
      "nesting.orphan_preview.dimensions",
      width: format_preview_dimension_mm(width_mm),
      height: format_preview_dimension_mm(height_mm)
    )
  end

  def padding
    Nesting::OrphansPresenter::PREVIEW_PADDING_MM
  end

  def split_preview_bounds(geometries, extra_rings: [])
    points = geometries.flat_map do |child|
      Array(child["rings"]).flat_map { |ring| Array(ring) }
    end
    extra_rings.each do |ring|
      points.concat(Array(ring))
    end
    return nil if points.empty?

    xs = points.map { |point| point.fetch(0).to_f }
    ys = points.map { |point| point.fetch(1).to_f }
    [ xs.min, ys.min, xs.max, ys.max ]
  end

  def split_mother_paths(rings, bounds:, padding:)
    minx, miny, _maxx, _maxy = bounds
    view_height = bounds_view_height(bounds, padding)
    Array(rings).map do |ring|
      tag.path(
        d: split_ring_path(ring, minx: minx, miny: miny, padding: padding, view_height: view_height),
        class: "split-plan-preview__mother",
        fill_rule: "evenodd",
        vector_effect: "non-scaling-stroke"
      )
    end
  end

  def split_child_paths(child, bounds:, padding:, child_index:)
    minx, miny, _maxx, _maxy = bounds
    child_class = child_index.odd? ? "split-plan-preview__child split-plan-preview__child--alt" : "split-plan-preview__child"
    Array(child["rings"]).map do |ring|
      tag.path(
        d: split_ring_path(ring, minx: minx, miny: miny, padding: padding, view_height: bounds_view_height(bounds, padding)),
        class: child_class,
        fill_rule: "evenodd",
        vector_effect: "non-scaling-stroke"
      )
    end
  end

  def split_cut_paths(cut_segments, bounds:, padding:)
    minx, miny, _maxx, _maxy = bounds
    view_height = bounds_view_height(bounds, padding)
    Array(cut_segments).map do |segment|
      start_point, end_point = segment
      tag.line(
        x1: start_point.fetch(0).to_f - minx + padding,
        y1: view_height - (start_point.fetch(1).to_f - miny) - padding,
        x2: end_point.fetch(0).to_f - minx + padding,
        y2: view_height - (end_point.fetch(1).to_f - miny) - padding,
        class: "split-plan-preview__cut"
      )
    end
  end

  def split_ring_path(ring, minx:, miny:, padding:, view_height:)
    ring.each_with_index.map do |(x, y), index|
      svg_x = x.to_f - minx + padding
      svg_y = view_height - (y.to_f - miny) - padding
      prefix = index.zero? ? "M" : "L"
      "#{prefix} #{svg_x} #{svg_y}"
    end.join(" ") + " Z"
  end

  def bounds_view_height(bounds, padding)
    (_minx, miny, _maxx, maxy) = bounds
    (maxy - miny) + (2 * padding)
  end

  def orphan_preview_label_id(orphan)
    "orphan-preview-#{orphan.piece_index}"
  end

  def orphan_preview_path(orphan)
    padding = Nesting::OrphansPresenter::PREVIEW_PADDING_MM
    orphan.rings.map { |ring| orphan_preview_ring_path(ring, orphan: orphan, padding: padding) }.join(" ")
  end

  def orphan_preview_ring_path(ring, orphan:, padding:)
    ring.each_with_index.map do |(x, y), index|
      svg_x = x - orphan.offset_x_mm + padding
      svg_y = orphan.view_height - (y - orphan.offset_y_mm) - padding
      prefix = index.zero? ? "M" : "L"
      "#{prefix} #{svg_x} #{svg_y}"
    end.join(" ") + " Z"
  end

  def format_preview_dimension_mm(value)
    rounded = value.to_f
    rounded == rounded.round ? rounded.round.to_s : format("%.1f", rounded)
  end
end
