# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-002] Piece-to-piece clearance (mm); distinct from MarginMm.
  class KerfMm
    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "kerf_mm required" if raw.nil?

      new(raw)
    end

    def self.from_project(project)
      parse(project.kerf_mm)
    end

    def initialize(raw)
      @value = Float(raw)
      raise ArgumentError, "kerf_mm must be non-negative" if @value.negative?
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
