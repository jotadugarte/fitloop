# frozen_string_literal: true

# Shared nesting job kickoff for NestingRunsController and ProjectLayersController.
module StartsNesting
  extend ActiveSupport::Concern

  private

  def start_nesting_for!(project, nest_updated_pieces: false)
    # [REQ-FIT-JOB-001] Drop prior nest artifacts so ProjectStatusSync does not treat stale
    # placements_json as proof the new processing run already finished.
    if project.nested_dxf.attached? || project.placements_json.attached?
      SheetStocks::InvalidateNestingOutputs.call(project)
    end

    snapshot = {}
    snapshot["nest_updated_pieces"] = true if nest_updated_pieces
    nesting_run = project.nesting_runs.create!(status: "processing", params_snapshot: snapshot)
    project.update!(
      status: :processing,
      progress_percent: 3,
      progress_message: I18n.t("nesting.queued"),
      estimated_finished_at: Time.current + 30.seconds
    )
    Nesting::ProgressBroadcaster.call(project: project.reload, eta_overrun: false, time_limit_notice: false)
    NestingJob.perform_later(nesting_run.id)
    nesting_run
  end

  def renesting?(project)
    project.nested_dxf.attached? && (project.completed? || project.partial?)
  end
end
