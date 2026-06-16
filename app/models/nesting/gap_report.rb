# frozen_string_literal: true

module Nesting
  class GapReport
    attr_reader :gaps

    def self.from_json(json_data)
      data = case json_data
             when String
               JSON.parse(json_data)
             when Array
               json_data
             else
               []
             end
      gaps = data.map do |entry|
        dist = entry.is_a?(Hash) ? entry["distance_mm"] : entry
        GapDistanceMm.new(dist)
      end
      new(gaps)
    end

    def initialize(gaps)
      @gaps = Array(gaps)
    end

    def blocking?
      @gaps.any?(&:blocking?)
    end

    def warnable?
      @gaps.any?(&:warnable?) && @gaps.none?(&:blocking?)
    end

    def auto_closeable?
      @gaps.all? { |g| g.value <= 15.0 }
    end

    def unresolved?(auto_close_gaps: false)
      @gaps.any? do |g|
        if g.blocking?
          true
        elsif g.warnable?
          !auto_close_gaps
        else
          false
        end
      end
    end
  end
end
