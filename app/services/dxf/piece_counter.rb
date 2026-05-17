# frozen_string_literal: true

require "open3"
require "json"

module Dxf
  # [REQ-FIT-VAL-001] Counts closed contours on selected layers via nesting_engine.
  class PieceCounter
    SCRIPT = Rails.root.join("nesting_engine/count_pieces.py").freeze

    class Error < StandardError; end

    def self.count(paths:, layer_names:)
      return 0 if paths.blank? || layer_names.blank?

      output, status = Open3.capture2(
        Python.executable,
        SCRIPT.to_s,
        layer_names.to_json,
        *paths.map(&:to_s)
      )
      raise Error, output.presence || "piece count failed" unless status.success?

      JSON.parse(output).fetch("piece_count")
    end
  end
end
