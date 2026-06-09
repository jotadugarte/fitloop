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

    validation_errors = validate_uploaded_files(files)
    if validation_errors.any?
      respond_to_validation_errors(validation_errors)
      return
    end

    attachment_ids_before = @project.input_dxf_attachments.map(&:id)
    files.each { |file| @project.input_dxf.attach(file) }
    Dxf::LayerSyncPerFile.call(@project)
    @project.reload
    assign_layer_expand_state!(attachment_ids_before)

    if attachment_ids_before.empty? && @project.input_dxf_attachments.any?
      first_attachment = @project.input_dxf_attachments.first
      layers = @project.project_layers.where(active_storage_attachment_id: first_attachment.id).pluck(:layer_name)
      Analytics::TrackEvent.call(
        "first_dxf_uploaded",
        user_id: current_user&.id,
        anonymous_session_key: session[:anonymous_session_key],
        tab_id: workspace_tab_id,
        project_id: @project.id,
        ip: request.remote_ip,
        user_agent: request.user_agent,
        country_code: Analytics::ResolveCountry.call(request),
        locale: I18n.locale.to_s,
        properties: {
          filename: first_attachment.filename.to_s,
          byte_size: first_attachment.byte_size.to_i,
          layers: layers
        }
      )
    end

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
    Array(list).flatten.compact
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

  def validate_uploaded_files(files)
    errors = []
    files.each do |file|
      if file.size > 10.megabytes
        errors << t("project_layers.upload.too_large", filename: file.original_filename)
      elsif !file.original_filename.to_s.downcase.end_with?(".dxf")
        errors << t("project_layers.upload.invalid_extension", filename: file.original_filename)
      else
        content = File.binread(file.tempfile.path, 1024) || ""
        unless content.include?("SECTION")
          errors << t("project_layers.upload.corrupt_dxf", filename: file.original_filename)
        end
      end
    end
    errors
  end

  def respond_to_validation_errors(errors)
    msg = errors.join(" ")
    respond_to do |format|
      format.turbo_stream do
        flash[:alert] = msg
        redirect_to workshop_path, status: :see_other
      end
      format.html do
        redirect_to workshop_path, alert: msg
      end
    end
  end
end
