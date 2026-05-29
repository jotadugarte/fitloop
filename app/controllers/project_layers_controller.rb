# frozen_string_literal: true

# [REQ-FIT-DXF-001] Layer checklist built from union of uploaded DXF layer names.
# [REQ-FIT-DXF-002] Per-file primary layer + auxiliary layers when using per-file sync.
class ProjectLayersController < ApplicationController
  include StartsNesting
  include SetsWorkspaceProject
  include BlocksWorkshopDuringPendingPayment

  before_action :set_workspace_project

  def index
    sync_layers!
    @project.reload
    @per_file_layers = per_file_layers?
    @project_layers = @project.project_layers.order(:layer_name)
    @input_dxf_attachments = @project.input_dxf_attachments
    @readiness = ProjectReadinessValidator.validate(@project)
  end

  def update
    return if reject_workshop_mutation_if_pending_payment!

    ProjectLayerSelection.apply!(project: @project, raw_params: params[:project_layers])

    readiness = ProjectReadinessValidator.validate(@project)
    unless readiness.ok?
      redirect_to project_layers_path(@project), alert: readiness.errors.join(" ")
      return
    end

    start_nesting_for!(@project)
    redirect_to workshop_path
  end

  private

  def sync_layers!
    return if @project.input_dxf_attachments.blank?

    if per_file_layers? || @project.input_dxf_attachments.one?
      Dxf::LayerSyncPerFile.call(@project)
    else
      Dxf::LayerSync.call(@project)
    end
  end

  def per_file_layers?
    @project.project_layers.where.not(active_storage_attachment_id: nil).exists?
  end
end
