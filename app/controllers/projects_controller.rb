# frozen_string_literal: true

# [REQ-FIT-UI-001] Ephemeral workspace setup and project show.
class ProjectsController < ApplicationController
  include SetsWorkspaceProject

  layout :fitloop_layout

  before_action :set_workspace_project, only: %i[
    show edit update verify_pin nesting_sync nesting_parameters workspace nested_dxf
  ]
  before_action :require_project_access!, only: %i[edit update]
  def index
    redirect_to start_project_path
  end

  def show
    grant_project_access!(@project) if @project.ephemeral?
    return render("projects/pin_gate", status: :ok) unless project_access_granted?(@project)

    sync_nesting_ui_state!
    @time_limit_notice = @project.partial? && @project.progress_message == I18n.t("nesting.time_limit_notice")
    @nesting_preview = Nesting::PreviewPresenter.for(@project)
    @nesting_orphans = Nesting::OrphansPresenter.for(@project)
  end

  def nested_dxf
    grant_project_access!(@project) if @project.ephemeral?
    return render("projects/pin_gate", status: :ok) unless project_access_granted?(@project)

    attachment = @project.nested_dxf
    return head(:not_found) unless attachment.attached?

    send_data(
      attachment.download,
      filename: attachment.filename.to_s,
      type: attachment.content_type,
      disposition: "attachment"
    )
  end

  def nesting_sync
    grant_project_access!(@project) if @project.ephemeral?
    return head(:forbidden) unless project_access_granted?(@project)

    sync_nesting_ui_state!
    @time_limit_notice = @project.partial? && @project.progress_message == I18n.t("nesting.time_limit_notice")
    @nesting_preview = Nesting::PreviewPresenter.for(@project)
    @nesting_orphans = Nesting::OrphansPresenter.for(@project)

    render turbo_stream: nesting_sync_streams, formats: :turbo_stream
  end

  def start
    Workspace.discard!(session)
    redirect_to new_project_path
  end

  def new
    @project = Workspace.find_or_create!(session)
    grant_project_access!(@project)
    @composer_draft = {}
  end

  def create
    redirect_to new_project_path
  end

  def edit
    grant_project_access!(@project) if @project.ephemeral?
    @composer_draft = {}
    render(:new) if @project.ephemeral?
  end

  def update
    attributes = normalized_project_attributes
    sync_sheet_inventory!(@project, attributes["sheet_stocks_attributes"])
    @project.assign_attributes(attributes)
    normalize_sheet_stock_consumption_order!(@project)

    if @project.ephemeral?
      finish_ephemeral_setup
    elsif @project.save
      redirect_to @project, notice: t("projects.updated")
    else
      @composer_draft = composer_draft_params
      render(:edit, status: :unprocessable_content)
    end
  end

  def verify_pin
    if ProjectAccess.granted?(project: @project, pin: params[:pin])
      grant_project_access!(@project)
      redirect_to @project, notice: t("projects.access.granted")
    else
      flash.now[:alert] = t("projects.access.denied")
      render("projects/pin_gate", status: :unprocessable_entity)
    end
  end

  def nesting_parameters
    grant_project_access!(@project) if @project.ephemeral?
    return head(:forbidden) unless project_access_granted?(@project)

    if @project.update(nesting_parameters_params)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            project_dom_id(:nesting_parameters),
            partial: "projects/nesting_parameters",
            locals: { project: @project }
          )
        end
        format.html { redirect_to @project, notice: t("projects.nesting_parameters_updated") }
      end
    else
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            project_dom_id(:nesting_parameters),
            partial: "projects/nesting_parameters",
            locals: { project: @project }
          ), status: :unprocessable_content
        end
        format.html { redirect_to @project, alert: @project.errors.full_messages.to_sentence }
      end
    end
  end

  def workspace
    grant_project_access!(@project) if @project.ephemeral?
    return head(:forbidden) unless project_access_granted?(@project)

    case params[:section]
    when "sheets"
      update_workspace_sheets!
    when "layers"
      update_workspace_layers!
    else
      head :unprocessable_entity
    end
  end

  private

  def update_workspace_sheets!
    attributes = workspace_sheet_params
    sync_sheet_inventory!(@project, attributes["sheet_stocks_attributes"])
    @project.assign_attributes(attributes)
    normalize_sheet_stock_consumption_order!(@project)

    if @project.save
      SheetStocks::InvalidateNestingOutputs.call(@project) if @project.nested_dxf.attached? || @project.placements_json.attached?
      @project.reload
      render_workspace_turbo_stream(:sheets)
    else
      render_workspace_turbo_stream(:sheets, status: :unprocessable_content)
    end
  end

  def update_workspace_layers!
    ProjectLayerSelection.apply!(project: @project, raw_params: params[:project_layers])
    render_workspace_turbo_stream(:layers)
  end

  def render_workspace_turbo_stream(section, status: :ok)
    streams = case section
              when :sheets
                @project.reload
                sheet_workspace_streams
              when :layers
                [
                  turbo_stream.replace(
                    project_dom_id(:source_dxf_detail),
                    partial: "projects/show_source_dxf_detail",
                    locals: { project: @project }
                  )
                ]
              else
                []
              end

    render turbo_stream: streams, status: status
  end

  def workspace_sheet_params
    attributes = params.require(:project).permit(
      sheet_stocks_attributes: %i[id width_mm height_mm quantity sort_order _destroy]
    ).to_h
    normalize_sheet_quantities!(attributes["sheet_stocks_attributes"])
    attributes
  end

  def finish_ephemeral_setup
    unless @project.save
      @composer_draft = composer_draft_params
      render(:new, status: :unprocessable_content)
      return
    end

    ProjectLayerSelection.apply!(project: @project, raw_params: params[:project_layers])

    if @project.input_dxf_attachments.blank?
      flash.now[:alert] = t("projects.setup.missing_dxf")
      @composer_draft = composer_draft_params
      render(:new, status: :unprocessable_content)
      return
    end

    readiness = ProjectReadinessValidator.validate(@project)
    unless readiness.ok?
      flash.now[:alert] = readiness.errors.join(" ")
      @composer_draft = composer_draft_params
      render(:new, status: :unprocessable_content)
      return
    end

    Workspace.bind!(session, @project)
    @project.update!(status: :ready)
    redirect_to @project
  end

  def fitloop_layout
    pin_gate_request? ? "minimal" : "application"
  end

  def pin_gate_request?
    return true if action_name == "verify_pin"
    return false unless action_name == "show" && @project
    return false if @project.ephemeral?

    !project_access_granted?(@project)
  end

  def require_project_access!
    return if @project.ephemeral?

    super(@project)
  end

  def nesting_parameters_params
    params.require(:project).permit(:kerf_mm, :margin_mm)
  end

  def project_params
    params.require(:project).permit(
      :title,
      :pin,
      :kerf_mm,
      :margin_mm,
      sheet_stocks_attributes: %i[id width_mm height_mm quantity sort_order _destroy]
    )
  end

  def normalized_project_attributes
    attributes = project_params.to_h
    normalize_sheet_quantities!(attributes["sheet_stocks_attributes"])
    attributes
  end

  def normalize_sheet_quantities!(sheet_stocks_attributes)
    return if sheet_stocks_attributes.blank?

    sheet_stocks_attributes.each_value do |attrs|
      next unless attrs.is_a?(Hash)

      quantity = attrs[:quantity].presence || attrs["quantity"].presence
      attrs[:quantity] = quantity.present? ? quantity.to_i : nil
    end
  end

  def normalize_sheet_stock_consumption_order!(project)
    SheetStocks::NormalizeConsumptionOrder.call(project)
  end

  def sync_sheet_inventory!(project, sheet_stocks_attributes)
    return if sheet_stocks_attributes.blank?

    SheetStocks::SyncInventory.call(
      project: project,
      sheet_stocks_attributes: sheet_stocks_attributes
    )
  end

  def composer_draft_params
    params.fetch(:composer_draft, {}).permit(:width_mm, :height_mm, :quantity).to_h
  end

  def sync_nesting_ui_state!
    Nesting::ProjectStatusSync.call(project: @project)
    @project.reload
  end

  def sheet_workspace_streams
    [
      turbo_stream.replace(
        project_dom_id(:sheet_inventory),
        partial: "projects/show_sheet_inventory",
        locals: { project: @project }
      ),
      turbo_stream.replace(
        project_dom_id(:show_actions),
        partial: "projects/show_actions",
        locals: { project: @project }
      ),
      turbo_stream.replace(
        project_dom_id(:status_badge),
        partial: "projects/status_badge",
        locals: { project: @project }
      )
    ]
  end

  def nesting_sync_streams
    streams = [
      turbo_stream.replace(
        project_dom_id(:nesting_progress),
        partial: "projects/nesting_progress",
        locals: nesting_progress_locals
      ),
      turbo_stream.replace(
        project_dom_id(:status_badge),
        partial: "projects/status_badge",
        locals: { project: @project }
      )
    ]

    unless @project.processing?
      streams << turbo_stream.replace(
        project_dom_id(:show_actions),
        partial: "projects/show_actions",
        locals: { project: @project }
      )
      streams << turbo_stream.replace(
        project_dom_id(:preview_zone),
        partial: "projects/show_preview_zone",
        locals: {
          project: @project,
          preview: @nesting_preview,
          orphans: @nesting_orphans
        }
      )
    end

    streams
  end

  def project_dom_id(*suffix)
    ActionView::RecordIdentifier.dom_id(@project, *suffix)
  end

  def nesting_progress_locals
    {
      project: @project,
      eta_overrun: @project.estimated_finished_at.present? && Time.current > @project.estimated_finished_at,
      time_limit_notice: @time_limit_notice
    }
  end
end
