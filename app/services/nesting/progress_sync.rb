# frozen_string_literal: true

module Nesting
  # [REQ-FIT-JOB-001] Applies CLI progress snapshots to the project and broadcasts UI updates.
  class ProgressSync
    def self.call(project:, snapshot:, nesting_run: nil, broadcast: true)
      new(project: project, snapshot: snapshot, nesting_run: nesting_run, broadcast: broadcast).call
    end

    def initialize(project:, snapshot:, nesting_run:, broadcast:)
      @project = project
      @snapshot = snapshot
      @nesting_run = nesting_run
      @broadcast = broadcast
    end

    def call
      return false if @snapshot.nil?

      attrs = build_attrs
      return false unless attrs_changed?(attrs)

      @project.update!(attrs)
      broadcast_progress! if @broadcast
      true
    end

    private

    def build_attrs
      attrs = {
        progress_percent: @snapshot.percent,
        progress_message: @snapshot.message_key
      }

      eta = compute_eta
      if eta.present?
        # [REQ-FIT-JOB-001] Monotonic: ETA can only decrease within a run.
        # If the new estimate is later than what we already have, keep the old one.
        # This prevents the timer from jumping forward when a slow step follows fast ones.
        if @project.estimated_finished_at.present? && eta > @project.estimated_finished_at
          eta = @project.estimated_finished_at
        end
        attrs[:estimated_finished_at] = eta
      end
      attrs
    end

    def compute_eta
      if @snapshot.eta_sec
        # [REQ-FIT-JOB-001] Prefer countdown from WallClockEtaEstimator when available.
        Time.current + @snapshot.eta_sec.seconds
      else
        time_limit = NestingTimeLimitSec.from_project(@project)
        ProgressEta.estimate(
          started_at: run_started_at,
          time_limit_sec: time_limit.to_i,
          pieces_total: @snapshot.pieces_total,
          pieces_placed: @snapshot.pieces_placed
        )
      end
    end

    def run_started_at
      @nesting_run&.started_at || @project.updated_at
    end

    def attrs_changed?(attrs)
      attrs.any? { |key, value| @project.public_send(key) != value }
    end

    def broadcast_progress!
      ProgressBroadcaster.call(
        project: @project,
        eta_overrun: eta_overrun?,
        time_limit_notice: false
      )
    end

    def eta_overrun?
      @project.estimated_finished_at.present? && Time.current > @project.estimated_finished_at
    end
  end
end
