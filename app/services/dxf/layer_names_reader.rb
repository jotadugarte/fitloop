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
  end
end
