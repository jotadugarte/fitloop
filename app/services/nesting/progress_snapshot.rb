# frozen_string_literal: true

module Nesting
  # [REQ-FIT-JOB-001] Parses CLI progress.json for live nesting UI updates.
  class ProgressSnapshot
    SCHEMA_VERSION = 1

    PHASE_I18N_KEYS = {
      "extracting" => "nesting.phase.extracting",
      "fill" => "nesting.phase.fill",
      "optimizing" => "nesting.phase.optimizing",
      "consolidating" => "nesting.phase.consolidating",
      "refining" => "nesting.phase.refining",
      "writing_outputs" => "nesting.phase.writing_outputs"
    }.freeze

    attr_reader :phase_id, :percent, :message_key, :pieces_total, :pieces_placed

    def self.read(work_dir, last_percent: 0)
      path = Pathname(work_dir).join("output", "progress.json")
      return nil unless path.file?

      from_hash(JSON.parse(path.read), last_percent: last_percent)
    rescue JSON::ParserError
      nil
    end

    def self.from_hash(hash, last_percent: 0)
      data = hash.transform_keys(&:to_s)
      return nil unless data["version"] == SCHEMA_VERSION

      phase_id = data["phase_id"].to_s
      return nil unless PHASE_I18N_KEYS.key?(phase_id)

      percent = Integer(data["percent"])
      return nil if percent.negative? || percent > 100
      return nil if percent < last_percent

      message_key = data["message_key"].presence || PHASE_I18N_KEYS.fetch(phase_id)
      new(
        phase_id: phase_id,
        percent: percent,
        message_key: message_key,
        pieces_total: optional_integer(data["pieces_total"]),
        pieces_placed: optional_integer(data["pieces_placed"])
      )
    end

    def initialize(phase_id:, percent:, message_key:, pieces_total: nil, pieces_placed: nil)
      @phase_id = phase_id
      @percent = percent
      @message_key = message_key
      @pieces_total = pieces_total
      @pieces_placed = pieces_placed
    end

    def message
      I18n.t(message_key)
    end

    def self.optional_integer(value)
      return nil if value.nil?

      Integer(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :optional_integer
  end
end
