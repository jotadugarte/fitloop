# frozen_string_literal: true

# [REQ-FIT-UI-001] Project CRUD with ordered sheet inventory.
class ProjectsController < ApplicationController
  layout :fitloop_layout

  before_action :set_project, only: %i[show edit update verify_pin nesting_sync]
  before_action :require_project_access!, only: %i[edit update]

  def index
    @projects = Project.order(created_at: :desc)
    @project_cards = @projects.map { |project| [ project, Nesting::PreviewPresenter.for(project) ] }
  end

  def show
    return render("projects/pin_gate", status: :ok) unless project_access_granted?(@project)

    sync_nesting_ui_state!
    @time_limit_notice = @project.partial? && @project.progress_message == I18n.t("nesting.time_limit_notice")
    @source_dxf_preview = Dxf::SourcePreviewPresenter.for(@project)
    @nesting_preview = Nesting::PreviewPresenter.for(@project)
    @nesting_orphans = Nesting::OrphansPresenter.for(@project)
    @nesting_runs = @project.nesting_runs.order(created_at: :desc)
  end

  def nesting_sync
    return head(:forbidden) unless project_access_granted?(@project)

    sync_nesting_ui_state!
    @time_limit_notice = @project.partial? && @project.progress_message == I18n.t("nesting.time_limit_notice")
    @source_dxf_preview = Dxf::SourcePreviewPresenter.for(@project)
    @nesting_preview = Nesting::PreviewPresenter.for(@project)
    @nesting_orphans = Nesting::OrphansPresenter.for(@project)

    render turbo_stream: nesting_sync_streams, formats: :turbo_stream
  end

  def new
    @project = Project.new
    @composer_draft = {}
  end

  def create
    @project = Project.new(normalized_project_attributes)
    @project.pin = project_params[:pin] if project_params[:pin].present?

    assign_sheet_stock_sort_orders!(@project)

    if @project.save
      grant_project_access!(@project)
      attach_dxf_files!(@project)
      Dxf::LayerSync.call(@project) if @project.input_dxf_attachments.any?
      redirect_to project_layers_path(@project), notice: t("projects.created")
    else
      @composer_draft = composer_draft_params
      render(:new, status: :unprocessable_content)
    end
  end

  def update
    @project.assign_attributes(normalized_project_attributes)
    @project.pin = project_params[:pin] if project_params[:pin].present?

    assign_sheet_stock_sort_orders!(@project)

    if @project.save
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

  private

  def fitloop_layout
    pin_gate_request? ? "minimal" : "application"
  end

  def pin_gate_request?
    return true if action_name == "verify_pin"
    return false unless action_name == "show" && @project

    !project_access_granted?(@project)
  end

  def require_project_access!
    super(@project)
  end

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(
      :title,
      :pin,
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
      attrs[:quantity] = quantity.present? ? quantity : nil
    end
  end

  def assign_sheet_stock_sort_orders!(project)
    project.sheet_stocks.reject(&:marked_for_destruction?).each_with_index do |stock, index|
      stock.sort_order = index
    end
  end

  def attach_dxf_files!(project)
    dxf_files_param.each { |file| project.input_dxf.attach(file) }
  end

  def dxf_files_param
    Array(params[:files]).compact.reject { |file| file.respond_to?(:size) && file.size.zero? }
  end

  def composer_draft_params
    params.fetch(:composer_draft, {}).permit(:width_mm, :height_mm, :quantity).to_h
  end

  def sync_nesting_ui_state!
    Nesting::ProjectStatusSync.call(project: @project)
    @project.reload
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
        project_dom_id(:nesting_preview),
        partial: "projects/nesting_preview",
        locals: { project: @project, preview: @nesting_preview }
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
      orphans: @nesting_orphans,
      eta_overrun: @project.estimated_finished_at.present? && Time.current > @project.estimated_finished_at,
      time_limit_notice: @time_limit_notice
    }
  end
end
