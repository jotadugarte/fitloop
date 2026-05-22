# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nest with updated pieces", type: :request do
  include ActiveJob::TestHelper

  def start_ephemeral_workspace!
    get start_project_path
    follow_redirect!
    Project.find(session[:workspace_project_id])
  end

  def prepare_partial_nest!(project)
    sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)
    project.sheet_stocks.create!(width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    project.update!(status: :partial)
  end

  describe "POST /projects/:project_id/nesting_runs [REQ-FIT-NEST-004] [REQ-FIT-SPLIT-001]" do
    let(:project) { start_ephemeral_workspace! }

    before do
      prepare_partial_nest!(project)
      project.derived_pieces.create!(
        parent_piece_key: "0",
        label: "Pieza-1a",
        geometry_json: {
          "rings" => [ [ [ 0.0, 0.0 ], [ 80.0, 0.0 ], [ 80.0, 40.0 ], [ 0.0, 40.0 ] ] ]
        },
        sort_order: 0
      )
    end

    it "[REQ-FIT-SPLIT-001] enqueues NestingJob when nest_updated_pieces is set" do
      expect do
        post project_nesting_runs_path(project), params: { nest_updated_pieces: true }
      end.to have_enqueued_job(NestingJob)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to be_nil

      run = project.nesting_runs.order(created_at: :desc).first
      expect(run.params_snapshot).to include("nest_updated_pieces" => true)
    end

    it "[REQ-FIT-JOB-001] [REQ-FIT-SPLIT-001] purges stale nest outputs and shows processing progress on redirect" do
      project.placements_json.attach(
        io: StringIO.new('{"placements":[]}'),
        filename: "placements.json",
        content_type: "application/json"
      )

      post project_nesting_runs_path(project), params: { nest_updated_pieces: true }

      project.reload
      expect(project).to be_processing
      expect(project.placements_json).not_to be_attached
      expect(project.progress_message).to eq("nesting.phase.queued")

      follow_redirect!
      expect(response.body).to include('data-testid="nesting-progress"')
      expect(response.body).to include(I18n.t("nesting.phase.queued"))
      expect(response.body).not_to include(I18n.t("nesting.completed"))
    end

    it "[REQ-FIT-SPLIT-001] rejects nest_updated_pieces without derived pieces" do
      project.derived_pieces.delete_all

      expect do
        post project_nesting_runs_path(project), params: { nest_updated_pieces: true }
      end.not_to have_enqueued_job(NestingJob)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to be_present
    end
  end

  describe "GET /projects/:id [REQ-FIT-NEST-004] [REQ-FIT-SPLIT-001]" do
    let(:project) { start_ephemeral_workspace! }

    before { prepare_partial_nest!(project) }

    it "[REQ-FIT-SPLIT-001] shows Anidar con piezas actualizadas after derived pieces exist" do
      project.derived_pieces.create!(
        parent_piece_key: "0",
        label: "Pieza-1a",
        geometry_json: {
          "rings" => [ [ [ 0.0, 0.0 ], [ 80.0, 0.0 ], [ 80.0, 40.0 ], [ 0.0, 40.0 ] ] ]
        },
        sort_order: 0
      )

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("nesting.nest_updated_pieces"))
      expect(response.body).to include('data-testid="nest-updated-pieces"')
    end

    it "[REQ-FIT-SPLIT-001] omits updated-pieces CTA when no derived pieces exist" do
      get project_path(project)

      expect(response.body).not_to include('data-testid="nest-updated-pieces"')
    end
  end
end
