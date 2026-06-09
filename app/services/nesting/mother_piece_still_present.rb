# frozen_string_literal: true

module Nesting
  # [REQ-FIT-SPLIT-001] Detects whether orphan mother geometry still extracts from project DXFs.
  class MotherPieceStillPresent
    def self.call(project:, mother_rings:, layer_name:)
      new(project: project, mother_rings: mother_rings, layer_name: layer_name).call
    end

    def initialize(project:, mother_rings:, layer_name:)
      @project = project
      @mother_rings = mother_rings
      @layer_name = layer_name
    end

    def call
      mother_key = piece_key_for_rings(@mother_rings)
      return false if mother_key.nil?

      current_pieces.any? { |rings| piece_key_for_rings(rings) == mother_key }
    end

    private

    def current_pieces
      with_downloaded_dxf_paths do |paths|
        Dxf::PieceRingsLister.list(paths: paths, layer_names: [ @layer_name ])
      end
    end

    def piece_key_for_rings(rings)
      attachment = @project.input_dxf_attachments.first
      return nil if attachment.nil?

      Nesting::PieceKeyBuilder.from_geometry(
        attachment: attachment,
        layer_name: @layer_name,
        rings: rings
      )
    end

    def with_downloaded_dxf_paths
      return yield [] if @project.input_dxf_attachments.blank?

      tempfiles = []
      paths = @project.input_dxf_attachments.map do |attachment|
        tempfile = Tempfile.new([ "fitloop_dxf", ".dxf" ], Dir.tmpdir)
        tempfiles << tempfile
        tempfile.binmode
        attachment.download { |chunk| tempfile.write(chunk) }
        tempfile.flush
        tempfile.path
      end
      yield paths
    ensure
      (tempfiles || []).each do |tempfile|
        tempfile.close
        tempfile.unlink
      end
    end
  end
end
