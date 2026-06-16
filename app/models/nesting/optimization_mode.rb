# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-002] CLI optimization_mode: fast (default) or thorough.
  class OptimizationMode
    MODES = %w[fast thorough].freeze

    attr_reader :value

    def self.from_env
      new(ENV.fetch("FITLOOP_NESTING_OPTIMIZATION_MODE", "fast"))
    end

    def initialize(raw)
      @value = raw.to_s.strip
      raise ArgumentError, "optimization_mode must be fast or thorough" unless MODES.include?(@value)
    end

    def to_s
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
