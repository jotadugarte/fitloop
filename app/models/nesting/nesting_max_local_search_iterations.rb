# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-002] Local-search iteration cap for thorough nesting.
  class NestingMaxLocalSearchIterations
    DEFAULT = 12

    attr_reader :value

    def self.from_env
      raw = ENV.fetch("FITLOOP_NESTING_MAX_LOCAL_SEARCH_ITERATIONS", DEFAULT.to_s)
      new(raw)
    end

    def initialize(raw)
      @value = Integer(raw)
      raise ArgumentError, "max_local_search_iterations must be non-negative" if @value.negative?
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
