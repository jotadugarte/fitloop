# frozen_string_literal: true

# [REQ-FIT-UI-002] [REQ-FIT-UI-004] Shared SVG preview rendering.
module NestingPreviewHelper
  SHEET_FILL_COLOR = "#ffffff"
  SHEET_BORDER_COLOR = "#152a45"
  SHEET_BORDER_WIDTH = 3

  def nesting_preview_svg(preview, css_class:, testid: nil, mini: false)
    tag.svg(
      class: css_class,
      viewBox: preview.view_box,
      xmlns: "http://www.w3.org/2000/svg",
      role: "img",
      aria: { hidden: mini },
      data: (testid ? { testid: testid } : {})
    ) do
      safe_join(
        preview.sheets.map do |sheet|
          nesting_preview_sheet_markup(
            sheet,
            layout_height: preview.sheet_layout_height,
            show_dimensions: !mini
          )
        end
      )
    end
  end

  private

  def nesting_preview_sheet_markup(sheet, layout_height:, show_dimensions: true)
    sheet_attrs = {
      x: sheet.offset_x_mm,
      y: sheet_top_svg_y(layout_height, sheet.height_mm),
      width: sheet.width_mm,
      height: sheet.height_mm
    }
    sheet_fill = tag.rect(**sheet_attrs, fill: SHEET_FILL_COLOR, stroke: "none", class: "nesting-preview__sheet-fill")
    piece_tags = sheet.pieces.map do |piece|
      nesting_preview_piece_markup(piece, sheet: sheet, layout_height: layout_height)
    end
    sheet_border = tag.rect(
      **sheet_attrs,
      fill: "none",
      stroke: SHEET_BORDER_COLOR,
      stroke_width: SHEET_BORDER_WIDTH,
      vector_effect: "non-scaling-stroke",
      class: "nesting-preview__sheet-border",
      data: { testid: "preview-sheet" }
    )
    labels = []
    if show_dimensions
      labels << nesting_preview_sheet_dimensions_label(sheet, layout_height: layout_height)
    end
    safe_join([ sheet_fill, *piece_tags, sheet_border, *labels ])
  end

  def nesting_preview_sheet_dimensions_label(sheet, layout_height:)
    tag.text(
      nesting_preview_sheet_dimensions_text(sheet),
      x: sheet.offset_x_mm + (sheet.width_mm / 2.0),
      y: layout_height + 28,
      class: "nesting-preview__sheet-size",
      text_anchor: "middle",
      data: { testid: "preview-sheet-dimensions" }
    )
  end

  def nesting_preview_sheet_dimensions_text(sheet)
    t(
      "projects.preview.sheet_dimensions",
      index: sheet.display_index,
      width: format_preview_dimension_mm(sheet.width_mm),
      height: format_preview_dimension_mm(sheet.height_mm)
    )
  end

  def format_preview_dimension_mm(value)
    rounded = value.to_f
    rounded == rounded.round ? rounded.round.to_s : format("%.1f", rounded)
  end

  def nesting_preview_piece_markup(piece, sheet:, layout_height:)
    if piece.rings.present?
      path_d = piece.rings.map { |ring| nesting_preview_ring_path(ring, sheet: sheet, layout_height: layout_height) }.join(" ")
      return tag.path(
        d: path_d,
        class: "nesting-preview__piece",
        fill_rule: "evenodd",
        vector_effect: "non-scaling-stroke",
        data: { testid: "preview-piece" }
      )
    end

    tag.rect(
      x: sheet.offset_x_mm + piece.x_mm,
      y: cad_y_to_svg_y(layout_height, piece.y_mm, piece.height_mm),
      width: piece.width_mm,
      height: piece.height_mm,
      class: "nesting-preview__piece",
      data: { testid: "preview-piece" }
    )
  end

  def nesting_preview_ring_path(ring, sheet:, layout_height:)
    ring.each_with_index.map do |(x, y), index|
      svg_x = sheet.offset_x_mm + x.to_f
      svg_y = layout_height - y.to_f
      prefix = index.zero? ? "M" : "L"
      "#{prefix} #{svg_x} #{svg_y}"
    end.join(" ") + " Z"
  end

  # CAD origin is bottom-left (Y up); SVG rects use top-left (Y down).
  def cad_y_to_svg_y(view_height, cad_bottom_y, height)
    view_height - cad_bottom_y - height
  end

  # Sheet spans CAD y=0..height with its bottom edge on the layout baseline.
  def sheet_top_svg_y(view_height, sheet_height_mm)
    view_height - sheet_height_mm
  end
end
