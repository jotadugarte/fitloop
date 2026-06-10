# frozen_string_literal: true

class Feedback
  # [REQ-FIT-OPS-001] Feedback body text with length bounds.
  class Message
    MIN_LENGTH = 5
    MAX_LENGTH = 5000

    attr_reader :value

    def self.parse(raw)
      stripped = raw.to_s.strip
      raise ArgumentError, "message required" if stripped.blank?
      raise ArgumentError, "message too short" if stripped.length < MIN_LENGTH
      raise ArgumentError, "message too long" if stripped.length > MAX_LENGTH

      new(stripped)
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
