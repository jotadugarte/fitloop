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
  end
end
