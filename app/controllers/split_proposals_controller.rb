# frozen_string_literal: true

# [REQ-FIT-SPLIT-001] Accept, reject, or regenerate split previews for an orphan.
class SplitProposalsController < ApplicationController
  include ProjectAccessGate
  include SetsWorkspaceProject

  before_action :set_workspace_project
  before_action -> { require_project_access!(@project) }
  before_action :ensure_ephemeral_workspace!
  before_action :set_orphan_resolution

  def accept
    proposal = current_draft_proposal!
    if proposal.split_not_feasible?
      redirect_to @project, alert: I18n.t("nesting.split.not_feasible_accept")
      return
    end

    Nesting::MaterializeSplitProposal.call(
      project: @project,
      orphan_resolution: @orphan_resolution,
      proposal: proposal
    )
    @project.reload
    Nesting::SplitWorkflowBroadcaster.call(project: @project)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @project }
    end
  end

  def reject
    proposal = current_draft_proposal!
    proposal.update!(status: :rejected)
    append_session_workflow_log!("split_rejected", proposal)
    redirect_to @project
  end

  def regenerate
    @orphan_resolution.split_proposals.draft.delete_all
    Nesting::SplitPlanJob.perform_later(@orphan_resolution.id)
    append_session_workflow_log!("split_regenerate_requested", nil)
    redirect_to @project
  end

  private

  def ensure_ephemeral_workspace!
    return if @project.ephemeral?

    head :forbidden
  end

  def set_orphan_resolution
    @orphan_resolution = @project.orphan_resolutions.find_by!(piece_key: params[:piece_key])
  end

  def current_draft_proposal!
    @orphan_resolution.split_proposals.draft.order(version: :desc).first!
  end

  def append_session_workflow_log!(event, proposal)
    log = Array(@project.session_workflow_log)
    entry = {
      "event" => event,
      "piece_key" => @orphan_resolution.piece_key,
      "at" => Time.current.iso8601
    }
    entry["split_proposal_id"] = proposal.id if proposal
    log << entry
    @project.update!(session_workflow_log: log)
  end
end
