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

  def orphan_preview_dimensions(orphan)
    t(
      "nesting.orphan_preview.dimensions",
      width: format_preview_dimension_mm(orphan.width_mm),
      height: format_preview_dimension_mm(orphan.height_mm)
    )
  end

  private

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
