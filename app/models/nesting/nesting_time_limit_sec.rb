# frozen_string_literal: true

module Nesting
  # [REQ-FIT-JOB-001] Nesting job/engine deadline in seconds.
  class NestingTimeLimitSec
    attr_reader :value

    def self.parse(raw)
      raise ArgumentError, "nesting_time_limit_sec required" if raw.nil?

      new(raw)
    end

    def self.from_project(project)
      parse(project.nesting_time_limit_sec)
    end

    def initialize(raw)
      @value = Integer(raw)
      raise ArgumentError, "nesting_time_limit_sec must be positive" unless @value.positive?
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
