# frozen_string_literal: true

module Nesting
  # [REQ-FIT-DOM-001] DXF curve tessellation tolerance (mm).
  class CurveToleranceMm
    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "curve_tolerance_mm required" if raw.nil?

      new(raw)
    end

    def self.from_project(project)
      parse(project.curve_tolerance_mm)
    end

    def initialize(raw)
      @value = Float(raw)
      raise ArgumentError, "curve_tolerance_mm must be positive" unless @value.positive?
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
