# frozen_string_literal: true

class Feedback
  # [REQ-FIT-OPS-001] Optional submitter email for anonymous feedback.
  class SenderEmail
    FORMAT = URI::MailTo::EMAIL_REGEXP

    attr_reader :value

    def self.parse(raw)
      return nil if raw.nil?

      stripped = raw.to_s.strip.downcase
      return nil if stripped.empty?

      new(stripped)
    end

    def initialize(value)
      @value = value.to_s.downcase
      raise ArgumentError, "invalid email" unless @value.match?(FORMAT)
      @value = @value.freeze
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
