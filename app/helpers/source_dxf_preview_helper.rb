# frozen_string_literal: true

# [REQ-FIT-UI-002] SVG preview of the original DXF (selected layers, original colors).
module SourceDxfPreviewHelper
  def source_dxf_preview_svg(preview, css_class:, testid: nil)
    tag.svg(
      class: css_class,
      viewBox: preview.view_box,
      xmlns: "http://www.w3.org/2000/svg",
      role: "img",
      data: (testid ? { testid: testid } : {})
    ) do
      safe_join(
        preview.layers.map { |layer| source_dxf_preview_layer_markup(layer, preview: preview) }
      )
    end
  end

  private

  def source_dxf_preview_layer_markup(layer, preview:)
    paths = layer.polylines.map do |line|
      tag.path(
        d: source_dxf_polyline_path(line, preview: preview),
        class: "source-dxf-preview__path",
        fill: "none",
        stroke: layer.color,
        vector_effect: "non-scaling-stroke"
      )
    end

    tag.g(class: "source-dxf-preview__layer", data: { layer: layer.name }) do
      safe_join(paths)
    end
  end

  def source_dxf_polyline_path(line, preview:)
    line.each_with_index.map do |(x, y), index|
      svg_x = x - preview.offset_x_mm
      svg_y = preview.view_height - (y - preview.offset_y_mm)
      prefix = index.zero? ? "M" : "L"
      "#{prefix} #{svg_x} #{svg_y}"
    end.join(" ")
  end
end
