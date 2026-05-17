# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project nesting preview", type: :request do
  let(:project) { Project.create!(title: "Preview bench", pin: "334422") }
  let(:placements_payload) do
    {
      sheets: [
        {
          stock_sort_order: 0,
          sheet_index: 0,
          width_mm: 1000.0,
          height_mm: 500.0,
          offset_x_mm: 0.0,
          pieces: [
            { piece_index: 0, x_mm: 10.0, y_mm: 15.0, rotation_deg: 0.0, width_mm: 80.0, height_mm: 40.0 }
          ]
        },
        {
          stock_sort_order: 0,
          sheet_index: 1,
          width_mm: 1000.0,
          height_mm: 500.0,
          offset_x_mm: 1015.0,
          pieces: []
        }
      ],
      orphans: []
    }
  end

  describe "GET /projects/:id [REQ-FIT-UI-002]" do
    it "renders an SVG preview with one rect per sheet in placements.json" do
      project.placements_json.attach(
        io: StringIO.new(placements_payload.to_json),
        filename: "placements.json",
        content_type: "application/json"
      )
      project.update!(status: :completed)

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="nesting-preview"')
      expect(response.body).to include('data-testid="nesting-preview-svg"')
      expect(response.body.scan('data-testid="preview-sheet"').size).to eq(2)
      expect(response.body).to include(I18n.t("projects.preview.sheet_count", count: 2))
    end
  end
end
