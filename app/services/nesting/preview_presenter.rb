# frozen_string_literal: true

module Nesting
  # [REQ-FIT-UI-002] SVG preview data from placements.json.
  class PreviewPresenter
    # Extra space between sheets in the SVG preview so boundaries read clearly (not in DXF output).
    VISUAL_SHEET_GAP_MM = 60.0
    SHEET_LABEL_BAND_MM = 40.0

    Sheet = Struct.new(:offset_x_mm, :width_mm, :height_mm, :pieces, :sheet_index, keyword_init: true) do
      def display_index
        sheet_index + 1
      end
    end
    Piece = Struct.new(:x_mm, :y_mm, :width_mm, :height_mm, :rings, keyword_init: true)

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
      @sheets ||= build_sheets_for_display
    end

    def view_width
      sheets.map { |sheet| sheet.offset_x_mm + sheet.width_mm }.max || 1.0
    end

    def sheet_layout_height
      sheets.map(&:height_mm).max || 1.0
    end

    def view_height
      sheet_layout_height + SHEET_LABEL_BAND_MM
    end

    def view_box
      "0 0 #{view_width} #{view_height}"
    end

    private

    def load_data
      return unless @project.placements_json.attached?

      JSON.parse(@project.placements_json.download)
    end

    def build_sheets_for_display
      rows = Array(@data&.fetch("sheets", [])).sort_by { |row| row.fetch("offset_x_mm").to_f }
      cursor_x = 0.0

      rows.map.with_index do |row, index|
        sheet = build_sheet(row, display_offset_x_mm: cursor_x, fallback_sheet_index: index)
        cursor_x += row.fetch("width_mm").to_f + VISUAL_SHEET_GAP_MM
        sheet
      end
    end

    def build_sheet(row, display_offset_x_mm:, fallback_sheet_index:)
      pieces = Array(row["pieces"]).map do |piece_row|
        Piece.new(
          x_mm: piece_row.fetch("x_mm").to_f,
          y_mm: piece_row.fetch("y_mm").to_f,
          width_mm: piece_row.fetch("width_mm", 0).to_f,
          height_mm: piece_row.fetch("height_mm", 0).to_f,
          rings: piece_row["rings"]
        )
      end

      Sheet.new(
        offset_x_mm: display_offset_x_mm,
        width_mm: row.fetch("width_mm").to_f,
        height_mm: row.fetch("height_mm").to_f,
        pieces: pieces,
        sheet_index: row.fetch("sheet_index", fallback_sheet_index).to_i
      )
    end
  end
end
