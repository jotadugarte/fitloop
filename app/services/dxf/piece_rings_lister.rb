# frozen_string_literal: true

require "open3"
require "json"

module Dxf
  # [REQ-FIT-SPLIT-001] Lists closed-contour rings from current project DXF inputs.
  class PieceRingsLister
    SCRIPT = Rails.root.join("nesting_engine/list_piece_rings.py").freeze

    class Error < StandardError; end

    def self.list(paths:, layer_names:)
      return [] if paths.blank? || layer_names.blank?

      output, status = Open3.capture2(
        Python.subprocess_env,
        Python.executable,
        SCRIPT.to_s,
        layer_names.to_json,
        *paths.map(&:to_s)
      )
      raise Error, output.presence || "piece rings list failed" unless status.success?

      JSON.parse(output).fetch("pieces")
    end
  end
end
