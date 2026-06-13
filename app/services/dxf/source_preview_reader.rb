# frozen_string_literal: true

require "open3"
require "json"
require "digest"

module Dxf
  # Reads layer-filtered DXF geometry with original layer colors for the source preview.
  class SourcePreviewReader
    SCRIPT = Rails.root.join("nesting_engine/dxf_preview.py").freeze

    class Error < StandardError; end

    def self.preview(paths:, curve_tolerance_mm:, layer_names: nil, input_files: nil)
      return empty_payload if paths.blank?
      return empty_payload if layer_names.blank? && input_files.blank?

      config = { curve_tolerance_mm: curve_tolerance_mm }
      if input_files.present?
        config[:input_files] = input_files
      else
        config[:layer_names] = layer_names
      end

      dxf_bytes = paths.map { |p| File.binread(p) }.join
      config_json = config.to_json
      cache_key = "source_preview/#{Digest::SHA256.hexdigest(dxf_bytes + config_json)}"

      Rails.cache.fetch(cache_key, expires_in: 24.hours) do
        output, status = Open3.capture2(
          Python.subprocess_env,
          Python.executable,
          SCRIPT.to_s,
          config_json,
          *paths.map(&:to_s)
        )
        raise Error, output.presence || "source preview failed" unless status.success?

        JSON.parse(output)
      end
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
