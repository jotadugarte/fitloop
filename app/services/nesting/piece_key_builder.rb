# frozen_string_literal: true

require "digest"

module Nesting
  # [REQ-FIT-SPLIT-001] Builds stable piece keys from DXF attachments and geometry.
  class PieceKeyBuilder
    FINGERPRINT_LENGTH = 16

    def self.call(attachment:, piece_index:)
      new.build_from_index(attachment: attachment, piece_index: piece_index)
    end

    def self.from_geometry(attachment:, layer_name:, rings:)
      new.build_from_geometry(attachment: attachment, layer_name: layer_name, rings: rings)
    end

    def build_from_index(attachment:, piece_index:)
      blob_id = blob_id_for!(attachment)
      index = Integer(piece_index)
      raise ArgumentError, "piece_index must be non-negative" if index.negative?

      PieceKey.new("#{blob_id}:piece-#{index}")
    end

    def build_from_geometry(attachment:, layer_name:, rings:)
      blob_id = blob_id_for!(attachment)
      fingerprint = geometry_fingerprint(layer_name: layer_name, rings: rings)

      PieceKey.new("#{blob_id}:fp-#{fingerprint}")
    end

    private

    def blob_id_for!(attachment)
      raise ArgumentError, "attachment is required" if attachment.nil?

      blob_id = attachment.blob_id
      raise ArgumentError, "attachment blob is required" if blob_id.nil?

      blob_id
    end

    def geometry_fingerprint(layer_name:, rings:)
      payload = {
        layer_name: layer_name.to_s,
        rings: normalize_rings(rings)
      }.to_json

      Digest::SHA256.hexdigest(payload).first(FINGERPRINT_LENGTH)
    end

    def normalize_rings(rings)
      Array(rings).map do |ring|
        Array(ring).map { |point| normalize_point(point) }
      end
    end

    def normalize_point(point)
      coords = Array(point)
      raise ArgumentError, "ring point must have x and y" if coords.size < 2

      [
        coords.fetch(0).to_f.round(3),
        coords.fetch(1).to_f.round(3)
      ]
    end
  end
end
