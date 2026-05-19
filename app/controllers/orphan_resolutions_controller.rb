# frozen_string_literal: true

# [REQ-FIT-SPLIT-001] Update per-orphan resolution state in the ephemeral workspace.
class OrphanResolutionsController < ApplicationController
  include ProjectAccessGate
  include SetsWorkspaceProject

  before_action :set_workspace_project
  before_action -> { require_project_access!(@project) }
  before_action :ensure_ephemeral_workspace!

  def update
    resolution = @project.orphan_resolutions.find_or_initialize_by(piece_key: params[:piece_key])
    resolution.assign_attributes(orphan_resolution_params)
    resolution.save!

    append_session_workflow_log!(resolution)
    enqueue_split_plan_job!(resolution) if resolution.system_split?
    redirect_to @project
  end

  def confirm_manual
    resolution = @project.orphan_resolutions.find_by!(piece_key: params[:piece_key])
    unless resolution.manual?
      redirect_to @project, alert: I18n.t("nesting.split.manual.not_manual_state")
      return
    end

    result = Nesting::ConfirmManualOrphanResolution.call(
      project: @project,
      orphan_resolution: resolution
    )
    if result.ok?
      redirect_to @project, notice: I18n.t("nesting.split.manual.resolved")
    else
      redirect_to @project, alert: result.errors.join(" ")
    end
  end

  private

  def ensure_ephemeral_workspace!
    return if @project.ephemeral?

    head :forbidden
  end

  def orphan_resolution_params
    params.require(:orphan_resolution).permit(:resolution_state, :reason)
  end

  def enqueue_split_plan_job!(resolution)
    Nesting::SplitPlanJob.perform_later(resolution.id)
  end

  def append_session_workflow_log!(resolution)
    log = Array(@project.session_workflow_log)
    log << {
      "event" => "orphan_resolution_updated",
      "piece_key" => resolution.piece_key,
      "resolution_state" => resolution.resolution_state,
      "at" => Time.current.iso8601
    }
    @project.update!(session_workflow_log: log)
  end
end
