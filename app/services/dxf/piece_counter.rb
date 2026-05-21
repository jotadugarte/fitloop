# frozen_string_literal: true

require "open3"
require "json"

module Dxf
  # [REQ-FIT-VAL-001] Counts closed contours on selected layers via nesting_engine.
  class PieceCounter
    SCRIPT = Rails.root.join("nesting_engine/count_pieces.py").freeze

    class Error < StandardError; end

    # [REQ-FIT-DXF-002] Composite mode counts cut outlines on the primary layer only.
    def self.layer_names_for_count(project_layers)
      included = project_layers.where(included: true)
      if included.where(layer_role: :primary).exists?
        included.where(layer_role: :primary).pluck(:layer_name)
      else
        included.pluck(:layer_name)
      end
    end

    def self.count(paths:, layer_names:)
      return 0 if paths.blank? || layer_names.blank?

      output, status = Open3.capture2(
        Python.subprocess_env,
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
