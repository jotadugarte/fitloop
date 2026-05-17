# frozen_string_literal: true

module Nesting
  # [REQ-FIT-NEST-003] Orphan pieces from nesting with optional geometry for preview.
  class OrphansPresenter
    PREVIEW_PADDING_MM = 8.0

    Orphan = Struct.new(
      :piece_index,
      :reason,
      :rings,
      :width_mm,
      :height_mm,
      :offset_x_mm,
      :offset_y_mm,
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
      if placement_rows.any? && placement_rows.first.key?("rings")
        return placement_rows.map { |row| build_orphan(row) }
      end

      Array(latest_report&.fetch("orphans", nil)).map { |row| build_orphan(row) }
    end

    def build_orphan(row)
      Orphan.new(
        piece_index: row.fetch("piece_index").to_i,
        reason: row.fetch("reason"),
        rings: normalize_rings(row["rings"]),
        width_mm: row.fetch("width_mm", 0).to_f,
        height_mm: row.fetch("height_mm", 0).to_f,
        offset_x_mm: row.fetch("offset_x_mm", 0).to_f,
        offset_y_mm: row.fetch("offset_y_mm", 0).to_f
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
