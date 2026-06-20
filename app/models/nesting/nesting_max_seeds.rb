# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-002] Multi-start seed cap for thorough nesting (CLI max_seeds).
  class NestingMaxSeeds
    DEFAULT = 16

    attr_reader :value

    def self.from_env
      raw = ENV.fetch("FITLOOP_NESTING_MAX_SEEDS", DEFAULT.to_s)
      new(raw)
    end

    def initialize(raw)
      @value = Integer(raw)
      raise ArgumentError, "max_seeds must be positive" unless @value.positive?
    end

    def to_i
      @value
    end

    def ==(other)
      other.is_a?(self.class) && other.value == @value
    end

    alias eql? ==

    def hash
      @value.hash
    end
  end
end
