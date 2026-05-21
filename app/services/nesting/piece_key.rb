# frozen_string_literal: true

module Nesting
  # [REQ-FIT-SPLIT-001] Stable identifier for a nestable piece across runs.
  class PieceKey
    FORMAT = /\A\d+:(?:piece-\d+|fp-[a-f0-9]{16})\z/

    attr_reader :value

    def initialize(value)
      raise ArgumentError, "piece key is required" if value.blank?

      normalized = value.to_s
      raise ArgumentError, "invalid piece key format" unless normalized.match?(FORMAT)

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
