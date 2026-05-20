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
        progress_message: @snapshot.message
      }

      eta = ProgressEta.estimate(
        started_at: run_started_at,
        time_limit_sec: @project.nesting_time_limit_sec,
        pieces_total: @snapshot.pieces_total,
        pieces_placed: @snapshot.pieces_placed
      )
      attrs[:estimated_finished_at] = eta if eta.present?
      attrs
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
