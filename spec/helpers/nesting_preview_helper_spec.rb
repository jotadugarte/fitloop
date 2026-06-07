# frozen_string_literal: true

require "rails_helper"

RSpec.describe NestingPreviewHelper, "[REQ-FIT-UI-002]", type: :helper do
  describe "sheet dimension labels in preview SVG" do
    it "renders whole numbers without decimals and fractional values with one decimal" do
      project = create_project_for_spec!(title: "Preview dimensions")
      project.placements_json.attach(
        io: StringIO.new(
          {
            sheets: [
              {
                offset_x_mm: 0,
                width_mm: 1200,
                height_mm: 1200.4,
                sheet_index: 0,
                pieces: []
              }
            ]
          }.to_json
        ),
        filename: "placements.json",
        content_type: "application/json"
      )
      preview = Nesting::PreviewPresenter.for(project)
      svg = helper.nesting_preview_svg(preview, css_class: "nesting-preview", testid: "preview")

      expect(svg).to include("1200")
      expect(svg).to include("1200.4")
    end
  end

  describe "preview rendering branches [REQ-FIT-UI-002]" do
    let(:piece) do
      Nesting::PreviewPresenter::Piece.new(
        x_mm: 10,
        y_mm: 10,
        width_mm: 20,
        height_mm: 15,
        primary_layer_name: "CUT",
        rings: [],
        decorations: [
          Nesting::PreviewPresenter::Decoration.new(
            layer_name: "GRAB",
            geometry_type: "line",
            payload: { "coordinates" => [ [ 0, 0 ] ] }
          ),
          Nesting::PreviewPresenter::Decoration.new(
            layer_name: "MARK",
            geometry_type: "text",
            payload: { "insert" => "invalid" }
          )
        ]
      )
    end
    let(:sheet) do
      Nesting::PreviewPresenter::Sheet.new(
        offset_x_mm: 0,
        width_mm: 100,
        height_mm: 80,
        sheet_index: 0,
        pieces: [ piece ]
      )
    end
    let(:preview) do
      instance_double(
        Nesting::PreviewPresenter,
        view_box: "0 0 100 100",
        sheet_layout_height: 80,
        sheets: [ sheet ],
        color_for_layer: "#ff0000"
      )
    end

    it "renders mini previews without dimension labels" do
      svg = helper.nesting_preview_svg(preview, css_class: "nesting-preview", mini: true)

      expect(svg).to include('aria-hidden="true"')
      expect(svg).not_to include("preview-sheet-dimensions")
    end

    it "falls back to bounds markup and skips invalid decorations" do
      svg = helper.nesting_preview_svg(preview, css_class: "nesting-preview", testid: "preview")

      expect(svg).to include('data-testid="preview-piece"')
      expect(svg).not_to include("preview-decoration")
    end
  end
end
