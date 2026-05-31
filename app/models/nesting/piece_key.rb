# frozen_string_literal: true

module Nesting
  # [REQ-FIT-SPLIT-001] Stable identifier for a nestable piece across runs.
  class PieceKey
    LEGACY_FORMAT = /\A\d+\z/
    STABLE_FORMAT = /\A\d+:(?:piece-\d+|fp-[a-f0-9]{16})\z/
    FORMAT = /\A(?:\d+|\d+:(?:piece-\d+|fp-[a-f0-9]{16}))\z/

    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "piece key is required" if raw.blank?

      new(raw)
    end

    def initialize(value)
      raise ArgumentError, "piece key is required" if value.blank?

      normalized = value.to_s
      unless normalized.match?(FORMAT)
        raise ArgumentError, "invalid piece key format"
      end

      @value = normalized.freeze
    end

    def to_s
      value
    end

    def ==(other)
      other.is_a?(self.class) && other.value == value
    end

    alias eql? ==

    def hash
      value.hash
    end
  end
end
