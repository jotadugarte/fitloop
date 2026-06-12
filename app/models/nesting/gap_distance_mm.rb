# frozen_string_literal: true

module Nesting
  class GapDistanceMm
    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "gap distance required" if raw.nil?

      new(raw)
    end

    def initialize(raw)
      @value = Float(raw)
      raise ArgumentError, "gap distance must be non-negative" if @value.negative?
    end

    def silent_tolerable?
      @value <= 2.0
    end

    def warnable?
      @value > 2.0 && @value <= 15.0
    end

    def blocking?
      @value > 15.0
    end

    def to_f
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
