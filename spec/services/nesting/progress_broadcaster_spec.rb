# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProgressBroadcaster, "[REQ-FIT-JOB-001]" do
  let(:project) { create_project_for_spec!(title: "Broadcast bench") }

  describe ".call" do
    it "broadcasts nesting progress and, when not processing, actions and preview" do
      allow(project).to receive(:processing?).and_return(false)
      allow(project).to receive(:broadcast_replace_to)
      preview = instance_double(Nesting::PreviewPresenter)
      orphans = instance_double(Nesting::OrphansPresenter)
      allow(Nesting::PreviewPresenter).to receive(:for).with(project).and_return(preview)
      allow(Nesting::OrphansPresenter).to receive(:for).with(project).and_return(orphans)

      described_class.call(project: project, eta_overrun: true, time_limit_notice: false)

      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :nesting_progress),
        partial: "projects/nesting_progress",
        locals: hash_including(
          project: project,
          eta_overrun: true,
          time_limit_notice: false
        )
      )
      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :show_actions),
        partial: "projects/show_actions",
        locals: { project: project }
      )
      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :preview_zone),
        partial: "projects/show_preview_zone",
        locals: { project: project, preview: preview, orphans: orphans }
      )
    end

    it "renders preview zone with orphans when project is partial" do
      project.update!(status: :partial, progress_percent: 100, progress_message: "done")
      project.nesting_runs.create!(
        status: "partial",
        report_json: { "orphans" => [{ "piece_index" => 0, "reason" => "oversized_for_sheet" }] },
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
                rings: [ [ [ 0.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 100.0 ], [ 0.0, 100.0 ] ] ]
              }
            ]
          }.to_json
        ),
        filename: "placements.json",
        content_type: "application/json"
      )
      orphans = Nesting::OrphansPresenter.for(project)

      preview = Nesting::PreviewPresenter.for(project)

      html = ApplicationController.render(
        partial: "projects/show_preview_zone",
        locals: { project: project, preview: preview, orphans: orphans }
      )

      expect(html).to include('data-testid="nesting-orphans"')
      expect(html).to include('data-testid="orphan-card"')
      expect(html).to include('data-testid="orphan-preview-svg"')
      expect(html).to include('data-testid="download-orphan-dxf"')
      expect(html).to match(/Pieza 1|Piece 1/)
    end

    it "broadcasts nesting progress and status badge while processing" do
      allow(project).to receive(:processing?).and_return(true)
      allow(project).to receive(:broadcast_replace_to)

      described_class.call(project: project, eta_overrun: false, time_limit_notice: false)

      expect(project).to have_received(:broadcast_replace_to).twice
      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :status_badge),
        partial: "projects/status_badge",
        locals: { project: project }
      )
    end

    it "includes active_run locals while processing [REQ-FIT-JOB-001]" do
      project.update!(
        status: :processing,
        progress_percent: 42,
        progress_message: "Placing pieces on sheets",
        estimated_finished_at: 8.minutes.from_now
      )
      active_run = project.nesting_runs.create!(status: "processing", params_snapshot: {})
      allow(project).to receive(:processing?).and_return(true)
      allow(project).to receive(:broadcast_replace_to)

      described_class.call(project: project, eta_overrun: false, time_limit_notice: false)

      expect(project).to have_received(:broadcast_replace_to).with(
        project,
        target: ActionView::RecordIdentifier.dom_id(project, :nesting_progress),
        partial: "projects/nesting_progress",
        locals: hash_including(
          project: project,
          active_run: active_run,
          eta_overrun: false,
          time_limit_notice: false
        )
      )
    end
  end
end
