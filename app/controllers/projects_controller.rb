# frozen_string_literal: true

# [REQ-FIT-UI-001] Ephemeral workshop at /taller with contextual setup mode.
class ProjectsController < ApplicationController
  include SetsWorkspaceProject
  include RequiresNestedDownloadAuthorization
  include BlocksWorkshopDuringPendingPayment

  layout "application"

  before_action -> { set_workspace_project(create_if_missing: true) }, only: :show
  before_action :set_workspace_project, only: %i[
    nesting_sync nesting_parameters workspace nested_dxf
  ]
  before_action :assign_workshop_ux, only: %i[show nesting_sync nesting_parameters]
  before_action :reject_workshop_mutation_if_pending_payment!, only: :nested_dxf
  before_action :authorize_nested_download!, only: :nested_dxf

  def index
    redirect_to start_project_path
  end

  def show
    return if sync_nesting_ui_state!

    @time_limit_notice = Nesting::LocalizedProgressMessage.time_limit_notice?(@project)
    @nesting_preview = Nesting::PreviewPresenter.for(@project)
    @nesting_orphans = Nesting::OrphansPresenter.for(@project)
    @plan_download_included = Billing::PlanDownloadAvailability.plan_included?(user: current_user)
  end

  def nested_dxf
    Billing::RecordPlanDownload.call(
      user: current_user,
      nesting_run: @nesting_run,
      via_download_token: params[:download_token].present?
    )

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
    return if sync_nesting_ui_state!

    @time_limit_notice = Nesting::LocalizedProgressMessage.time_limit_notice?(@project)
    @nesting_preview = Nesting::PreviewPresenter.for(@project)
    @nesting_orphans = Nesting::OrphansPresenter.for(@project)

    render turbo_stream: nesting_sync_streams, formats: :turbo_stream
  end

  def start
    Workspace.discard!(session, tab_id: workspace_tab_id, request: request)
    Workspace.find_or_create!(session, tab_id: workspace_tab_id, request: request)
    redirect_to workshop_path
  end

  def nesting_parameters
    parsed = Nesting::AssignNestingParameters.call(raw_params: nesting_parameters_params)
    unless parsed.ok?
      @project.errors.add(:base, parsed.errors.first)
      return render_nesting_parameters_failure
    end

    if @project.update(kerf_mm: parsed.kerf.to_f, margin_mm: parsed.margin.to_f)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: nesting_parameters_turbo_stream }
        format.html { redirect_to workshop_path, notice: t("projects.nesting_parameters_updated") }
      end
    else
      render_nesting_parameters_failure
    end
  end

  def workspace
    case params[:section]
    when "sheets"
      update_workspace_sheets!
    when "layers"
      update_workspace_layers!
    when "billing"
      update_workspace_billing!
    else
      head :unprocessable_entity
    end
  end

  private

  def update_workspace_sheets!
    return if reject_workshop_mutation_if_pending_payment!

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
    return if reject_workshop_mutation_if_pending_payment!

    ProjectLayerSelection.apply!(project: @project, raw_params: params[:project_layers])
    # Avoid replacing the layer form on autosave — rapid radio/check changes race with turbo streams.
    head :no_content
  end

  def update_workspace_billing!
    policy = Billing::RegionalPolicy.from_request(request: request, session: session, user: current_user)
    billing = params.require(:billing).permit(:payment_method)
    payment_method = billing[:payment_method].presence || policy.fetch(:default_payment_method).to_s
    unless policy.fetch(:available_payment_methods).map(&:to_s).include?(payment_method)
      payment_method = policy.fetch(:default_payment_method).to_s
    end

    session[:billing_currency] = policy.fetch(:currency).to_s
    session[:billing_payment_method] = payment_method

    if params[:billing_return_to] == "paywall"
      redirect_to download_paywall_workshop_path
      return
    end

    head :ok
  rescue ActionController::ParameterMissing, KeyError
    head :unprocessable_entity
  end

  def render_workspace_turbo_stream(section, status: :ok)
    streams = case section
    when :sheets
      @project.reload
      sheet_workspace_streams
    else
      []
    end

    render turbo_stream: streams, status: status
  end

  def assign_workshop_ux
    return unless @project

    @workshop_ux = Workshop::UxMode.new(@project)
  end

  def workshop_ux
    @workshop_ux ||= Workshop::UxMode.new(@project)
  end

  def nesting_parameters_turbo_stream
    if workshop_ux.setup?
      turbo_stream.replace(
        project_dom_id(:setup_nesting_settings),
        partial: "projects/show_setup_nesting_settings",
        locals: { project: @project }
      )
    else
      turbo_stream.replace(
        project_dom_id(:nesting_parameters),
        partial: "projects/nesting_parameters",
        locals: { project: @project, workshop_ux: workshop_ux }
      )
    end
  end

  def render_nesting_parameters_failure
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: nesting_parameters_turbo_stream, status: :unprocessable_content
      end
      format.html { redirect_to workshop_path, alert: @project.errors.full_messages.to_sentence }
    end
  end

  def workspace_sheet_params
    attributes = params.require(:project).permit(
      sheet_stocks_attributes: %i[id width_mm height_mm quantity sort_order _destroy]
    ).to_h
    normalize_sheet_quantities!(attributes["sheet_stocks_attributes"])
    attributes
  end

  def nesting_parameters_params
    params.require(:project).permit(:kerf_mm, :margin_mm)
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

  def sync_nesting_ui_state!
    @project = Nesting::ProjectStatusSync.call(project: @project)
    return false if @project.present?

    redirect_to(start_project_path, alert: I18n.t("workspace.expired"))
    true
  end

  def sheet_workspace_streams
    [
      turbo_stream.replace(
        project_dom_id(:sheet_inventory),
        partial: "projects/show_sheet_inventory",
        locals: { project: @project, workshop_ux: workshop_ux }
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
      if workshop_ux.show_preview_zone?
        streams << turbo_stream.replace(
          project_dom_id(:preview_zone),
          partial: "projects/show_preview_zone",
          locals: {
            project: @project,
            preview: @nesting_preview,
            orphans: @nesting_orphans,
            plan_download_included: Billing::PlanDownloadAvailability.plan_included?(user: current_user)
          }
        )
      end
    end

    streams
  end

  def project_dom_id(*suffix)
    ActionView::RecordIdentifier.dom_id(@project, *suffix)
  end

  def nesting_progress_locals
    Nesting::ProgressLocals.for(@project, time_limit_notice: @time_limit_notice)
  end
end
