# frozen_string_literal: true

# [REQ-FIT-UI-002] SVG preview of the original DXF (selected layers, original colors).
module SourceDxfPreviewHelper
  def source_dxf_preview_svg(preview, css_class:, testid: nil, filter: nil, zoom_to_corrections: false)
    vbox = zoom_to_corrections ? preview.corrections_view_box : preview.view_box
    tag.svg(
      class: css_class,
      viewBox: vbox,
      xmlns: "http://www.w3.org/2000/svg",
      role: "img",
      data: (testid ? { testid: testid } : {})
    ) do
      markup = preview.layers.map { |layer| source_dxf_preview_layer_markup(layer, preview: preview, filter: filter) }.compact
      safe_join(markup)
    end
  end

  private

  def source_dxf_preview_layer_markup(layer, preview:, filter: nil)
    elements = []

    polylines_to_render = if filter == :valid
                            layer.polylines.reject(&:is_open)
                          elsif filter == :open
                            layer.polylines.select(&:is_open)
                          else
                            layer.polylines
                          end

    elements.concat(
      polylines_to_render.map do |line|
        tag.path(
          d: source_dxf_polyline_path(line, preview: preview),
          class: "source-dxf-preview__path",
          fill: "none",
          stroke: layer.color,
          vector_effect: "non-scaling-stroke"
        )
      end
    )

    if filter.nil? || filter == :open
      elements.concat(
        layer.auto_close_lines.map do |line|
          tag.path(
            d: source_dxf_polyline_path(line, preview: preview),
            class: "source-dxf-preview__auto-close-line",
            fill: "none",
            stroke: "#ff9f43",
            stroke_width: "2.5px",
            stroke_dasharray: "6 4",
            vector_effect: "non-scaling-stroke",
            data: { testid: "proposed-auto-close-line" }
          )
        end
      )

      Array(layer.gaps).each do |gap|
        next if gap[:auto_closed]
        next if gap[:distance_mm] <= 2.0

        cx = (gap[:start][0] + gap[:end][0]) / 2.0
        cy = (gap[:start][1] + gap[:end][1]) / 2.0

        svg_x = cx - preview.offset_x_mm
        svg_y = preview.view_height - (cy - preview.offset_y_mm)

        elements << tag.circle(
          cx: svg_x,
          cy: svg_y,
          r: 30,
          fill: "#ff4d4d",
          fill_opacity: 0.4,
          stroke: "#ff4d4d",
          stroke_width: 4,
          class: "source-dxf-preview__gap-circle",
          vector_effect: "non-scaling-stroke",
          style: "animation: pulse 1.2s infinite ease-in-out;",
          data: { testid: "gap-error-circle", distance: gap[:distance_mm] }
        )
      end
    end

    return nil if elements.empty?

    tag.g(class: "source-dxf-preview__layer", data: { layer: layer.name }) do
      safe_join(elements)
    end
  end

  def source_dxf_polyline_path(line, preview:)
    points = line.respond_to?(:points) ? line.points : line
    points.each_with_index.map do |(x, y), index|
      svg_x = x - preview.offset_x_mm
      svg_y = preview.view_height - (y - preview.offset_y_mm)
      prefix = index.zero? ? "M" : "L"
      "#{prefix} #{svg_x} #{svg_y}"
    end.join(" ")
  end
end
