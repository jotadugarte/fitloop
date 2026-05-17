# frozen_string_literal: true

# [REQ-FIT-UI-002] [REQ-FIT-UI-004] Shared SVG preview rendering.
module NestingPreviewHelper
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
        preview.sheets.map { |sheet| nesting_preview_sheet_markup(sheet, view_height: preview.view_height) }
      )
    end
  end

  private

  def nesting_preview_sheet_markup(sheet, view_height:)
    sheet_tag = tag.rect(
      x: sheet.offset_x_mm,
      y: cad_y_to_svg_y(view_height, sheet.height_mm, sheet.height_mm),
      width: sheet.width_mm,
      height: sheet.height_mm,
      class: "nesting-preview__sheet",
      data: { testid: "preview-sheet" }
    )
    piece_tags = sheet.pieces.map do |piece|
      tag.rect(
        x: sheet.offset_x_mm + piece.x_mm,
        y: cad_y_to_svg_y(view_height, piece.y_mm, piece.height_mm),
        width: piece.width_mm,
        height: piece.height_mm,
        class: "nesting-preview__piece",
        data: { testid: "preview-piece" }
      )
    end
    safe_join([ sheet_tag, *piece_tags ])
  end

  # CAD origin is bottom-left (Y up); SVG rects use top-left (Y down).
  def cad_y_to_svg_y(view_height, cad_bottom_y, height)
    view_height - cad_bottom_y - height
  end
end
