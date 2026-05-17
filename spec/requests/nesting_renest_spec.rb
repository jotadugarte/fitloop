# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Re-nesting", type: :request do
  let(:project) do
    Project.create!(
      title: "Re-nest bench",
      pin: "889900",
      status: :completed,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  before do
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)
    project.nested_dxf.attach(
      io: StringIO.new("OLD NESTED DXF"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    project.nesting_runs.create!(
      status: "completed",
      params_snapshot: {},
      started_at: 2.hours.ago,
      finished_at: 1.hour.ago
    )
    unlock_project_for_spec!(project, pin: "889900")
  end

  describe "POST /projects/:project_id/nesting_runs [REQ-FIT-NEST-004]" do
    it "creates a new nesting run and keeps prior runs in history" do
      expect do
        post project_nesting_runs_path(project)
      end.to change { project.nesting_runs.count }.by(1)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq(I18n.t("nesting.renest_started"))

      follow_redirect!
      expect(response.body).to include(I18n.t("nesting.renest_started"))
      expect(response.body.scan('data-testid="nesting-run-row"').size).to eq(2)
    end
  end

  describe "GET /projects/:id [REQ-FIT-NEST-004]" do
    it "shows download link and re-nest button when a nested DXF exists" do
      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="download-nested-dxf"')
      expect(response.body).to include('data-testid="renest-nesting"')
      expect(response.body).to include(I18n.t("nesting.renest"))
      expect(response.body).to include('data-controller="nesting-progress-sync"')
    end
  end
end
