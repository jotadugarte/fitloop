# frozen_string_literal: true

module Nesting
  # [REQ-FIT-CLI-001] SSOT for CLI numeric nesting parameters from a Project.
  class JobParameters
    attr_reader :kerf, :margin, :curve_tolerance, :sheet_gap, :time_limit

    def self.from_project(project)
      new(
        kerf: KerfMm.from_project(project),
        margin: MarginMm.from_project(project),
        curve_tolerance: CurveToleranceMm.from_project(project),
        sheet_gap: SheetGapMm.from_project(project),
        time_limit: NestingTimeLimitSec.from_project(project)
      )
    end

    def initialize(kerf:, margin:, curve_tolerance:, sheet_gap:, time_limit:)
      @kerf = kerf
      @margin = margin
      @curve_tolerance = curve_tolerance
      @sheet_gap = sheet_gap
      @time_limit = time_limit

      raise ArgumentError, "kerf required" unless @kerf.is_a?(KerfMm)
      raise ArgumentError, "margin required" unless @margin.is_a?(MarginMm)
      raise ArgumentError, "curve_tolerance required" unless @curve_tolerance.is_a?(CurveToleranceMm)
      raise ArgumentError, "sheet_gap required" unless @sheet_gap.is_a?(SheetGapMm)
      raise ArgumentError, "time_limit required" unless @time_limit.is_a?(NestingTimeLimitSec)
    end

    def to_config_hash
      {
        kerf_mm: @kerf.to_f,
        margin_mm: @margin.to_f,
        curve_tolerance_mm: @curve_tolerance.to_f,
        sheet_gap_mm: @sheet_gap.to_f,
        time_limit_sec: @time_limit.to_i
      }
    end

    def ==(other)
      other.is_a?(self.class) &&
        other.kerf == @kerf &&
        other.margin == @margin &&
        other.curve_tolerance == @curve_tolerance &&
        other.sheet_gap == @sheet_gap &&
        other.time_limit == @time_limit
    end

    alias eql? ==

    def hash
      [ @kerf, @margin, @curve_tolerance, @sheet_gap, @time_limit ].hash
    end
  end
end
