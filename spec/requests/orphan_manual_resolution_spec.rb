# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orphan manual resolution", "[REQ-FIT-SPLIT-001]", type: :request do
  def attach_orphan_placements!(project, rings:)
    project.nesting_runs.create!(
      status: "partial",
      report_json: {
        "orphans" => [ { "piece_index" => 0, "reason" => "oversized_for_sheet" } ]
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
              width_mm: 500.0,
              height_mm: 500.0,
              offset_x_mm: 0.0,
              offset_y_mm: 0.0,
              rings: rings
            }
          ]
        }.to_json
      ),
      filename: "placements.json",
      content_type: "application/json"
    )
    project.update!(status: :partial)
  end

  def write_mother_dxf(path, rings)
    python = Rails.root.join("nesting_engine/.venv/bin/python")
    script = <<~PY
      import ezdxf
      doc = ezdxf.new("R2010")
      doc.modelspace().add_lwpolyline(
          #{rings.first.map { |point| [ point[0], point[1] ] }.inspect},
          close=True,
          dxfattribs={"layer": "PIECES"},
      )
      doc.saveas(#{path.to_s.inspect})
    PY
    system(python.to_s, "-c", script, exception: true)
  end

  let(:mother_rings) do
    [
      [
        [ 0.0, 0.0 ],
        [ 500.0, 0.0 ],
        [ 500.0, 500.0 ],
        [ 0.0, 500.0 ]
      ]
    ]
  end

  describe "GET project show [REQ-FIT-SPLIT-001]" do
    let(:project) { start_ephemeral_workspace! }

    before do
      attach_orphan_placements!(project, rings: mother_rings)
      OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :manual
      )
    end

    it "[REQ-FIT-SPLIT-001] shows manual instructions without confirm button" do
      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="orphan-manual-flow"')
      expect(response.body).to include(I18n.t("nesting.split.manual.step_1", piece_number: 1))
      expect(response.body).to include(I18n.t("nesting.split.manual.step_2"))
      expect(response.body).not_to include(I18n.t("nesting.split.manual.no_dedup"))
      expect(response.body).not_to include('data-testid="confirm-manual-orphan"')
      expect(response.body).not_to include(I18n.t("nesting.split.manual.confirm"))
    end

    it "[REQ-FIT-SPLIT-001] disables system split when rings are missing" do
      project.placements_json.purge
      project.placements_json.attach(
        io: StringIO.new(
          {
            sheets: [],
            orphans: [
              {
                piece_index: 0,
                reason: "oversized_for_sheet",
                width_mm: 10.0,
                height_mm: 10.0,
                offset_x_mm: 0.0,
                offset_y_mm: 0.0,
                rings: []
              }
            ]
          }.to_json
        ),
        filename: "placements.json",
        content_type: "application/json"
      )

      get project_path(project)

      expect(response.body).to include('disabled="disabled"')
      expect(response.body).to include(I18n.t("nesting.split.choose_system"))
    end
  end

  describe "POST confirm_manual [REQ-FIT-SPLIT-001] [REQ-FIT-VAL-001]" do
    let(:project) { start_ephemeral_workspace! }
    let!(:resolution) do
      OrphanResolution.create!(
        project: project,
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :manual
      )
    end

    before do
      attach_orphan_placements!(project, rings: mother_rings)
      project.project_layers.create!(layer_name: "PIECES", included: true)
    end

    it "[REQ-FIT-SPLIT-001] resolves when mother geometry no longer extracts" do
      mother_path = Rails.root.join("tmp/manual_mother.dxf")
      write_mother_dxf(mother_path, mother_rings)
      project.input_dxf.attach(
        io: File.open(mother_path),
        filename: "mother.dxf",
        content_type: "application/dxf"
      )

      sample_path = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.purge
      project.input_dxf.attach(
        io: File.open(sample_path),
        filename: "sample_piece.dxf",
        content_type: "application/dxf"
      )

      post confirm_manual_project_orphan_resolution_path(project, resolution.piece_key)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:notice]).to eq(I18n.t("nesting.split.manual.resolved"))
      expect(resolution.reload.resolution_state).to eq("resolved")
      expect(project.reload.session_workflow_log.last).to include("event" => "manual_orphan_resolved")
    end

    it "[REQ-FIT-SPLIT-001] blocks confirm when mother geometry still extracts" do
      mother_path = Rails.root.join("tmp/manual_mother_still.dxf")
      write_mother_dxf(mother_path, mother_rings)
      project.input_dxf.attach(
        io: File.open(mother_path),
        filename: "mother.dxf",
        content_type: "application/dxf"
      )

      post confirm_manual_project_orphan_resolution_path(project, resolution.piece_key)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to eq(I18n.t("nesting.split.manual_mother_still_present"))
      expect(resolution.reload.resolution_state).to eq("manual")
    end

    it "[REQ-FIT-VAL-001] blocks confirm when project fails readiness" do
      post confirm_manual_project_orphan_resolution_path(project, resolution.piece_key)

      expect(response).to redirect_to(project_path(project))
      expect(flash[:alert]).to include(I18n.t("project_readiness.no_extractable_pieces"))
      expect(resolution.reload.resolution_state).to eq("manual")
    end
  end
end
