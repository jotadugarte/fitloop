# frozen_string_literal: true

require "open3"
require "json"
require "tempfile"

module Dxf
  # [REQ-FIT-NEST-003] Exports one orphan piece geometry to a DXF file.
  class OrphanPieceExporter
    SCRIPT = Rails.root.join("nesting_engine/write_piece_dxf.py").freeze

    class Error < StandardError; end

    def self.export(rings:, layer_name: "PIECES")
      new(rings: rings, layer_name: layer_name).export
    end

    def initialize(rings:, layer_name: "PIECES")
      @rings = rings
      @layer_name = layer_name
    end

    def export
      tempfile = Tempfile.new([ "fitloop_orphan", ".dxf" ], Dir.tmpdir)
      tempfile.close

      config = {
        output_path: tempfile.path,
        rings: @rings,
        layer_name: @layer_name
      }
      output, status = Open3.capture2(
        Python.subprocess_env,
        Python.executable,
        SCRIPT.to_s,
        config.to_json
      )
      raise Error, output.presence || "orphan DXF export failed" unless status.success?

      tempfile.path
    end
  end
end
