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
      safe_join(preview.sheets.map { |sheet| nesting_preview_sheet_markup(sheet) })
    end
  end

  private

  def nesting_preview_sheet_markup(sheet)
    sheet_tag = tag.rect(
      x: sheet.offset_x_mm,
      y: 0,
      width: sheet.width_mm,
      height: sheet.height_mm,
      class: "nesting-preview__sheet",
      data: { testid: "preview-sheet" }
    )
    piece_tags = sheet.pieces.map do |piece|
      tag.rect(
        x: sheet.offset_x_mm + piece.x_mm,
        y: piece.y_mm,
        width: piece.width_mm,
        height: piece.height_mm,
        class: "nesting-preview__piece",
        data: { testid: "preview-piece" }
      )
    end
    safe_join([ sheet_tag, *piece_tags ])
  end
end
