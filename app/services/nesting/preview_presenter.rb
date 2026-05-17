# frozen_string_literal: true

module Nesting
  # [REQ-FIT-UI-002] SVG preview data from placements.json.
  class PreviewPresenter
    Sheet = Struct.new(:offset_x_mm, :width_mm, :height_mm, :pieces, keyword_init: true)
    Piece = Struct.new(:x_mm, :y_mm, :width_mm, :height_mm, keyword_init: true)

    def self.for(project)
      new(project: project)
    end

    def initialize(project:)
      @project = project
      @data = load_data
    end

    def available?
      sheets.any?
    end

    def sheet_count
      sheets.size
    end

    def sheets
      @sheets ||= Array(@data&.fetch("sheets", [])).map { |row| build_sheet(row) }
    end

    def view_box
      width = sheets.map { |sheet| sheet.offset_x_mm + sheet.width_mm }.max || 1.0
      height = sheets.map(&:height_mm).max || 1.0
      "0 0 #{width} #{height}"
    end

    private

    def load_data
      return unless @project.placements_json.attached?

      JSON.parse(@project.placements_json.download)
    end

    def build_sheet(row)
      pieces = Array(row["pieces"]).map do |piece_row|
        Piece.new(
          x_mm: piece_row.fetch("x_mm").to_f,
          y_mm: piece_row.fetch("y_mm").to_f,
          width_mm: piece_row.fetch("width_mm", 0).to_f,
          height_mm: piece_row.fetch("height_mm", 0).to_f
        )
      end

      Sheet.new(
        offset_x_mm: row.fetch("offset_x_mm").to_f,
        width_mm: row.fetch("width_mm").to_f,
        height_mm: row.fetch("height_mm").to_f,
        pieces: pieces
      )
    end
  end
end
