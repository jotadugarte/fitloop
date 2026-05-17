# frozen_string_literal: true

# [REQ-FIT-UI-001] Project CRUD with ordered sheet inventory.
class ProjectsController < ApplicationController
  layout :fitloop_layout

  before_action :set_project, only: %i[show edit update verify_pin]
  before_action :require_project_access!, only: %i[edit update]

  def index
    @projects = Project.order(created_at: :desc)
    @project_cards = @projects.map { |project| [ project, Nesting::PreviewPresenter.for(project) ] }
  end

  def show
    return render("projects/pin_gate", status: :ok) unless project_access_granted?(@project)

    @time_limit_notice = @project.partial? && @project.progress_message == I18n.t("nesting.time_limit_notice")
    @nesting_preview = Nesting::PreviewPresenter.for(@project)
    @nesting_runs = @project.nesting_runs.order(created_at: :desc)
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(normalized_project_attributes)

    assign_sheet_stock_sort_orders!(@project)

    if @project.save
      grant_project_access!(@project)
      attach_dxf_files!(@project)
      Dxf::LayerSync.call(@project) if @project.input_dxf_attachments.any?
      redirect_to project_layers_path(@project), notice: t("projects.created")
    else
      render(:new, status: :unprocessable_content)
    end
  end

  def update
    @project.assign_attributes(normalized_project_attributes)

    assign_sheet_stock_sort_orders!(@project)

    if @project.save
      redirect_to @project, notice: t("projects.updated")
    else
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
end
