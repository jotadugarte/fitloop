# frozen_string_literal: true

require "open3"
require "json"

module Dxf
  # [REQ-FIT-DXF-001] Reads layer names and colors from DXF files via nesting_engine (ezdxf).
  class LayerNamesReader
    SCRIPT = Rails.root.join("nesting_engine/read_layers.py").freeze

    class Error < StandardError; end

    def self.catalog(paths)
      raise ArgumentError, "paths must be present" if paths.blank?

      output, status = Open3.capture2(
        Python.subprocess_env,
        Python.executable,
        SCRIPT.to_s,
        *paths.map(&:to_s)
      )
      raise Error, output.presence || "layer discovery failed" unless status.success?

      JSON.parse(output)
    end

    def self.union(paths)
      catalog(paths).pluck("name").sort
    end

    # [REQ-FIT-DXF-002] On-demand closed-contour gap scan for primary / legacy cut layers.
    def self.gaps_for(path:, layer_name:)
      raise ArgumentError, "path must be present" if path.blank?
      raise ArgumentError, "layer_name must be present" if layer_name.blank?

      output, status = Open3.capture2(
        Python.subprocess_env,
        Python.executable,
        SCRIPT.to_s,
        "--gaps-for",
        layer_name.to_s,
        path.to_s
      )
      raise Error, output.presence || "layer gap scan failed" unless status.success?

      JSON.parse(output)
    end
  end
end
