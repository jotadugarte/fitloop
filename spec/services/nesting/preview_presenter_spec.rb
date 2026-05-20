# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::PreviewPresenter do
  let(:project) { create_project_for_spec!(title: "Presenter bench", pin: "112244") }

  describe ".for [REQ-FIT-UI-002]" do
    it "reports sheet count from placements.json" do
      project.placements_json.attach(
        io: StringIO.new({ sheets: [{ offset_x_mm: 0, width_mm: 100, height_mm: 50, pieces: [] }, { offset_x_mm: 115, width_mm: 100, height_mm: 50, pieces: [] }] }.to_json),
        filename: "placements.json",
        content_type: "application/json"
      )

      presenter = described_class.for(project)

      expect(presenter.available?).to be(true)
      expect(presenter.sheet_count).to eq(2)
      expect(presenter.view_height).to eq(50 + described_class::SHEET_LABEL_BAND_MM)
    end

    it "exposes layer colors and parses composite decorations from placements.json" do
      project.project_layers.create!(
        layer_name: "CORTE",
        included: true,
        layer_role: :primary,
        color: "#ff0000"
      )
      project.project_layers.create!(
        layer_name: "GRABADO",
        included: true,
        layer_role: :auxiliary,
        color: "#260000"
      )
      project.placements_json.attach(
        io: StringIO.new(
          {
            sheets: [
              {
                offset_x_mm: 0,
                width_mm: 100,
                height_mm: 50,
                sheet_index: 0,
                pieces: [
                  {
                    piece_index: 0,
                    x_mm: 5,
                    y_mm: 5,
                    width_mm: 40,
                    height_mm: 40,
                    primary_layer_name: "CORTE",
                    rings: [ [ [ 5, 5 ], [ 45, 5 ], [ 45, 45 ], [ 5, 45 ] ] ],
                    decorations: [
                      {
                        layer_name: "GRABADO",
                        geometry_type: "line",
                        payload: { coordinates: [ [ 10, 20 ], [ 40, 20 ] ] }
                      }
                    ]
                  }
                ]
              }
            ]
          }.to_json
        ),
        filename: "placements.json",
        content_type: "application/json"
      )

      presenter = described_class.for(project)
      piece = presenter.sheets.first.pieces.first

      expect(presenter.color_for_layer("CORTE")).to eq("#ff0000")
      expect(presenter.color_for_layer("GRABADO")).to eq("#260000")
      expect(piece.decorations.size).to eq(1)
      expect(piece.decorations.first.layer_name).to eq("GRABADO")
    end
  end
end
