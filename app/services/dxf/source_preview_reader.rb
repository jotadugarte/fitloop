# frozen_string_literal: true

require "open3"
require "json"

module Dxf
  # Reads layer-filtered DXF geometry with original layer colors for the source preview.
  class SourcePreviewReader
    SCRIPT = Rails.root.join("nesting_engine/dxf_preview.py").freeze

    class Error < StandardError; end

    def self.preview(paths:, layer_names:, curve_tolerance_mm:)
      return empty_payload if paths.blank? || layer_names.blank?

      config = {
        layer_names: layer_names,
        curve_tolerance_mm: curve_tolerance_mm
      }
      output, status = Open3.capture2(
        Python.subprocess_env,
        Python.executable,
        SCRIPT.to_s,
        config.to_json,
        *paths.map(&:to_s)
      )
      raise Error, output.presence || "source preview failed" unless status.success?

      JSON.parse(output)
    end

    def self.empty_payload
      {
        "width_mm" => 1.0,
        "height_mm" => 1.0,
        "offset_x_mm" => 0.0,
        "offset_y_mm" => 0.0,
        "layers" => []
      }
    end
  end
end
