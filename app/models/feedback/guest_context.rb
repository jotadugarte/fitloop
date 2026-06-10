# frozen_string_literal: true

class Feedback
  # [REQ-FIT-OPS-001] Guest submission metadata for admin triage.
  class GuestContext
    ALLOWED_KEYS = %w[ip user_agent source_url].freeze
    MAX_ENTRIES = ALLOWED_KEYS.length

    attr_reader :attributes

    def self.from_request(request:, source_url: nil)
      raise ArgumentError, "request required" if request.nil?

      new(
        ip: request.remote_ip.to_s,
        user_agent: request.user_agent.to_s.truncate(512),
        source_url: source_url.to_s.presence
      )
    end

    def initialize(ip:, user_agent:, source_url: nil)
      @attributes = {
        "ip" => ip.to_s,
        "user_agent" => user_agent.to_s,
        "source_url" => source_url.to_s.presence
      }.compact.freeze
    end

    def to_h
      attributes.dup
    end

    def ==(other)
      other.is_a?(self.class) && other.attributes == attributes
    end

    alias eql? ==

    def hash
      attributes.hash
    end
  end
end
