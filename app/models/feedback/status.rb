# frozen_string_literal: true

class Feedback
  # [REQ-FIT-OPS-001] Feedback resolution status.
  class Status
    ALLOWED = %w[pending reviewed archived].freeze
    DEFAULT = "pending"

    attr_reader :value

    def self.parse(raw)
      value = raw.to_s.strip
      value = DEFAULT if value.blank?
      raise ArgumentError, "invalid status" unless ALLOWED.include?(value)

      new(value)
    end

    def initialize(value)
      @value = value.to_s.freeze
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
