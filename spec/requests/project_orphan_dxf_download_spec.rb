# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project orphan DXF download", type: :request do
  let(:project) { create_project_for_spec!(title: "Orphan DXF bench", pin: "665544") }

  def attach_orphan_placements!
    project.nesting_runs.create!(
      status: "partial",
      report_json: {
        "orphans" => [
          { "piece_index" => 0, "reason" => "oversized_for_sheet" }
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
              width_mm: 200.0,
              height_mm: 100.0,
              offset_x_mm: 0.0,
              offset_y_mm: 0.0,
              rings: [
                [ [ 0.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 100.0 ], [ 0.0, 100.0 ] ]
              ]
            }
          ]
        }.to_json
      ),
      filename: "placements.json",
      content_type: "application/json"
    )
    project.update!(status: :partial)
  end

  describe "GET /projects/:id/orphans/:piece_index/dxf [REQ-FIT-NEST-003]" do
    it "downloads a DXF for an orphan piece when access is granted" do
      unlock_project_for_spec!(project, pin: "665544")
      attach_orphan_placements!

      get orphan_dxf_project_path(project, piece_index: 0)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/dxf")
      expect(response.headers["Content-Disposition"]).to include("pieza_1.dxf")
      expect(response.body).to include("LWPOLYLINE")
    end

    it "returns not found for unknown piece index" do
      unlock_project_for_spec!(project, pin: "665544")
      attach_orphan_placements!

      get orphan_dxf_project_path(project, piece_index: 99)

      expect(response).to have_http_status(:not_found)
    end

    it "requires project access" do
      attach_orphan_placements!

      get orphan_dxf_project_path(project, piece_index: 0)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="pin-gate"')
    end
  end
end
