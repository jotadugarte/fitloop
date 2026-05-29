# frozen_string_literal: true

# [REQ-FIT-DXF-001] Multi-DXF upload during workspace setup and show.
class ProjectInputDxfFilesController < ApplicationController
  include SetsWorkspaceProject

  before_action :set_workspace_project

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
      format.html { redirect_to redirect_after_upload, notice: t("project_layers.upload.created") }
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
      format.html { redirect_to redirect_after_upload, notice: t("project_layers.upload.removed") }
    end
  end

  private

  def dxf_files_param
    list = params[:files]
    list = params[:"files[]"] if list.blank?
    Array(list).compact
  end

  def setup_context?
    params[:context].to_s == "setup"
  end

  def redirect_after_upload
    setup_context? ? edit_workshop_path : workshop_path
  end

  def respond_to_missing_files
    respond_to do |format|
      format.turbo_stream { head :unprocessable_content }
      format.html { redirect_to redirect_after_upload, alert: t("project_layers.upload.missing") }
    end
  end

  def assign_layer_expand_state!(attachment_ids_before)
    # Pre-condition: attachment list must exist to compute deltas.
    raise "missing attachment_ids_before" if attachment_ids_before.nil?

    # Only auto-expand layer details during initial setup.
    # In the workshop ("Mi taller"), panels must remain collapsed by default.
    @expand_layers = setup_context?
    @expanded_attachment_ids = if @expand_layers == true
      @project.input_dxf_attachments.map(&:id) - attachment_ids_before
    else
      []
    end

    # Post-condition: when not expanding, never leak expanded ids.
    raise "expanded_attachment_ids must be empty when not expanding" if @expand_layers != true && @expanded_attachment_ids.any?
  end

  def layer_expand_locals
    {
      expand_layers: @expand_layers == true,
      expanded_attachment_ids: Array(@expanded_attachment_ids)
    }
  end

  def render_dxf_stream
    @project.reload
    streams = if setup_context?
      [
        turbo_stream.replace(
          dom_id(@project, :dxf_files_layers),
          partial: "projects/dxf_files_layers",
          locals: { project: @project, context: "setup" }.merge(layer_expand_locals)
        )
      ]
    else
      [
        turbo_stream.replace(
          dom_id(@project, :source_dxf_detail),
          partial: "projects/show_source_dxf_detail",
          locals: { project: @project }.merge(layer_expand_locals)
        )
      ]
    end

    render turbo_stream: streams
  end

  def dom_id(record, prefix = nil)
    ActionView::RecordIdentifier.dom_id(record, prefix)
  end
end
