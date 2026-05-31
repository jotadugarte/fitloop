# frozen_string_literal: true

# [REQ-FIT-DXF-001] Multi-DXF upload during workspace setup and show.
class ProjectInputDxfFilesController < ApplicationController
  include SetsWorkspaceProject
  include BlocksWorkshopDuringPendingPayment

  before_action :set_workspace_project
  before_action :reject_workshop_mutation_if_pending_payment!, only: %i[create destroy]

  def create
    files = dxf_files_param
    if files.blank?
      respond_to_missing_files
      return
    end

    attachment_ids_before = @project.input_dxf_attachments.map(&:id)
    files.each { |file| @project.input_dxf.attach(file) }
    Dxf::LayerSyncPerFile.call(@project)
    @project.reload
    assign_layer_expand_state!(attachment_ids_before)

    respond_to do |format|
      format.turbo_stream { render_dxf_stream }
      format.html { redirect_to workshop_path, notice: t("project_layers.upload.created") }
    end
  end

  def destroy
    attachment = @project.input_dxf_attachments.find_by(id: params[:id])
    if attachment
      attachment.purge
      Dxf::LayerSyncPerFile.call(@project)
    end
    @expand_layers = false
    @expanded_attachment_ids = []

    respond_to do |format|
      format.turbo_stream { render_dxf_stream }
      format.html { redirect_to workshop_path, notice: t("project_layers.upload.removed") }
    end
  end

  private

  def dxf_files_param
    list = params[:files]
    list = params[:"files[]"] if list.blank?
    Array(list).compact
  end

  def respond_to_missing_files
    respond_to do |format|
      format.turbo_stream { head :unprocessable_content }
      format.html { redirect_to workshop_path, alert: t("project_layers.upload.missing") }
    end
  end

  def assign_layer_expand_state!(attachment_ids_before)
    raise "missing attachment_ids_before" if attachment_ids_before.nil?

    new_ids = @project.input_dxf_attachments.map(&:id) - attachment_ids_before
    @expand_layers = new_ids.any?
    @expanded_attachment_ids = new_ids
  end

  def layer_expand_locals
    {
      expand_layers: @expand_layers == true,
      expanded_attachment_ids: Array(@expanded_attachment_ids)
    }
  end

  def render_dxf_stream
    @project.reload
    render turbo_stream: turbo_stream.replace(
      dom_id(@project, :source_dxf_detail),
      partial: "projects/show_source_dxf_detail",
      locals: {
        project: @project,
        workshop_ux: Workshop::UxMode.new(@project)
      }.merge(layer_expand_locals)
    )
  end

  def dom_id(record, prefix = nil)
    ActionView::RecordIdentifier.dom_id(record, prefix)
  end
end
