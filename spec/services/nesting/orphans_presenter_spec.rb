# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::OrphansPresenter do
  let(:project) { create_project_for_spec!(title: "Orphans bench", pin: "887766") }

  describe ".for [REQ-FIT-NEST-003]" do
    it "builds preview data from placements.json orphan geometry" do
      project.nesting_runs.create!(
        status: "partial",
        report_json: {
          "orphans" => [
            { "piece_index" => 0, "reason" => "oversized_for_sheet" },
            { "piece_index" => 4, "reason" => "oversized_for_sheet" }
          ]
        },
        finished_at: Time.current
      )
      project.placements_json.attach(
        io: StringIO.new(
          {
            sheets: [],
            orphans: [
              {
                piece_index: 0,
                reason: "oversized_for_sheet",
                width_mm: 800.0,
                height_mm: 400.0,
                offset_x_mm: 10.0,
                offset_y_mm: 20.0,
                rings: [ [ [ 10.0, 20.0 ], [ 810.0, 20.0 ], [ 810.0, 420.0 ], [ 10.0, 420.0 ] ] ]
              },
              {
                piece_index: 4,
                reason: "oversized_for_sheet",
                width_mm: 120.0,
                height_mm: 50.0,
                offset_x_mm: 0.0,
                offset_y_mm: 0.0,
                rings: [ [ [ 0.0, 0.0 ], [ 120.0, 0.0 ], [ 120.0, 50.0 ], [ 0.0, 50.0 ] ] ]
              }
            ]
          }.to_json
        ),
        filename: "placements.json",
        content_type: "application/json"
      )

      presenter = described_class.for(project)

      expect(presenter.any?).to be(true)
      expect(presenter.items.size).to eq(2)
      expect(presenter.items.first.display_number).to eq(1)
      expect(presenter.items.first.preview_available?).to be(true)
      expect(presenter.items.first.view_width).to eq(816.0)
    end
  end
end
