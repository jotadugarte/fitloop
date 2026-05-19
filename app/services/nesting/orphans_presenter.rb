# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-003] Orphan pieces from nesting with optional geometry for preview.
  class OrphansPresenter
    PREVIEW_PADDING_MM = 8.0

    Orphan = Struct.new(
      :piece_index,
      :piece_key,
      :reason,
      :rings,
      :width_mm,
      :height_mm,
      :offset_x_mm,
      :offset_y_mm,
      :resolution_state,
      :split_proposal,
      keyword_init: true
    ) do
      def display_number
        piece_index + 1
      end

      def preview_available?
        exportable?
      end

      def exportable?
        rings.present? && rings.any? { |ring| ring.size >= 3 }
      end

      # [REQ-FIT-SPLIT-001] System split requires closed-ring geometry for preview/plan CLI.
      def system_split_enabled?
        exportable?
      end

      def split_preview_available?
        split_proposal&.draft? && split_proposal.child_piece_geometries.present?
      end

      def split_accepted?
        split_proposal&.accepted?
      end

      def view_width
        width_mm + (2 * PREVIEW_PADDING_MM)
      end

      def view_height
        height_mm + (2 * PREVIEW_PADDING_MM)
      end

      def view_box
        "0 0 #{view_width} #{view_height}"
      end
    end

    def self.for(project)
      new(project: project)
    end

    def initialize(project:)
      @project = project
    end

    def any?
      items.any?
    end

    def items
      @items ||= build_items
    end

    # Backward-compatible hash entries for callers expecting report shape.
    def entries
      items.map do |orphan|
        {
          "piece_index" => orphan.piece_index,
          "reason" => orphan.reason
        }
      end
    end

    def find_by_piece_index(piece_index)
      index = piece_index.to_i
      items.find { |orphan| orphan.piece_index == index }
    end

    private

    def build_items
      placement_rows = Array(placements_data&.fetch("orphans", nil))
      rows =
        if placement_rows.any? && placement_rows.first.key?("rings")
          placement_rows
        else
          Array(latest_report&.fetch("orphans", nil))
        end

      resolutions_by_key = @project.orphan_resolutions.index_by(&:piece_key)
      rows.filter_map { |row| build_orphan(row, resolutions_by_key) }
    end

    def build_orphan(row, resolutions_by_key)
      piece_index = row.fetch("piece_index").to_i
      piece_key = row["piece_key"].presence || piece_index.to_s
      resolution = resolutions_by_key[piece_key]
      return if resolution&.resolved?

      Orphan.new(
        piece_index: piece_index,
        piece_key: piece_key,
        reason: row.fetch("reason"),
        rings: normalize_rings(row["rings"]),
        width_mm: row.fetch("width_mm", 0).to_f,
        height_mm: row.fetch("height_mm", 0).to_f,
        offset_x_mm: row.fetch("offset_x_mm", 0).to_f,
        offset_y_mm: row.fetch("offset_y_mm", 0).to_f,
        resolution_state: resolution&.resolution_state || "pending",
        split_proposal: resolution&.split_proposals&.order(version: :desc)&.first
      )
    end

    def normalize_rings(rings)
      Array(rings).map do |ring|
        Array(ring).map { |point| [ point.fetch(0).to_f, point.fetch(1).to_f ] }
      end
    end

    def placements_data
      return unless @project.placements_json.attached?

      JSON.parse(@project.placements_json.download)
    rescue JSON::ParserError
      nil
    end

    def latest_report
      @project.nesting_runs.order(created_at: :desc).pick(:report_json)
    end
  end
end
