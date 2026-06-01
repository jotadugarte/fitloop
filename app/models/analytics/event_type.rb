# frozen_string_literal: true

module Analytics
  # Catalog-validated event type identifier.
  class EventType
    def self.parse(value)
      str = value.to_s.strip
      raise ArgumentError, "event_type required" if str.blank?

      unless EventCatalog.all_event_types.include?(str)
        raise ArgumentError, "Event type '#{str}' is not registered in the catalog"
      end

      new(str)
    end

    def initialize(value)
      @value = value.to_s.freeze
    end

    def to_s
      @value
    end

    def ==(other)
      other.is_a?(self.class) && other.to_s == to_s
    end

    alias eql? ==

    def hash
      @value.hash
    end
  end
end
