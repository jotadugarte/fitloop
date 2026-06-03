# frozen_string_literal: true

module Nesting
  # [REQ-FIT-JOB-001] Heuristic ETA from elapsed time and piece placement fraction.
  class ProgressEta
    MIN_FRACTION = 0.01

    def self.estimate(
      started_at:,
      time_limit_sec:,
      pieces_total: nil,
      pieces_placed: nil,
      now: Time.current
    )
      return nil if started_at.blank?

      limit_at = started_at + time_limit_sec.to_i.seconds
      total = pieces_total.to_i
      placed = pieces_placed.to_i
      return limit_at unless total.positive? && placed.positive?

      fraction = (placed.to_f / total).clamp(MIN_FRACTION, 1.0)
      elapsed_sec = (now - started_at).to_f
      return limit_at if elapsed_sec <= 0.0

      projected = started_at + (elapsed_sec / fraction).seconds
      [ projected, limit_at ].min
    end
  end
end
