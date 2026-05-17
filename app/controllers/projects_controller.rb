# frozen_string_literal: true

# [REQ-FIT-UI-001] Project CRUD with ordered sheet inventory.
class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update]

  def index
    @projects = Project.order(created_at: :desc)
  end

  def show
    @time_limit_notice = @project.partial? && @project.progress_message == I18n.t("nesting.time_limit_notice")
  end

  def new
    @project = Project.new
    build_sheet_stock_rows(row_count: 1)
  end

  def edit
    build_sheet_stock_rows(row_count: 1) if @project.sheet_stocks.empty?
  end

  def create
    @project = Project.new(normalized_project_attributes)

    if params[:add_sheet].present?
      @project.sheet_stocks.build(sort_order: @project.sheet_stocks.size)
      return render(:new, status: :unprocessable_content)
    end

    assign_sheet_stock_sort_orders!(@project)

    if @project.save
      redirect_to @project, notice: t("projects.created")
    else
      render(:new, status: :unprocessable_content)
    end
  end

  def update
    @project.assign_attributes(normalized_project_attributes)

    if params[:add_sheet].present?
      @project.sheet_stocks.build(sort_order: @project.sheet_stocks.size)
      return render(:edit, status: :unprocessable_content)
    end

    assign_sheet_stock_sort_orders!(@project)

    if @project.save
      redirect_to @project, notice: t("projects.updated")
    else
      render(:edit, status: :unprocessable_content)
    end
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(
      :title,
      :pin,
      sheet_stocks_attributes: %i[id width_mm height_mm quantity sort_order unlimited_quantity _destroy]
    )
  end

  def normalized_project_attributes
    attributes = project_params.to_h
    normalize_unlimited_quantities!(attributes["sheet_stocks_attributes"])
    attributes
  end

  def normalize_unlimited_quantities!(sheet_stocks_attributes)
    return if sheet_stocks_attributes.blank?

    sheet_stocks_attributes.each_value do |attrs|
      next unless attrs.is_a?(Hash)

      unlimited = attrs.delete(:unlimited_quantity) || attrs.delete("unlimited_quantity")
      attrs[:quantity] = nil if unlimited == "1"
    end
  end

  def build_sheet_stock_rows(row_count:)
    missing = row_count - @project.sheet_stocks.size
    missing.times { |offset| @project.sheet_stocks.build(sort_order: @project.sheet_stocks.size + offset) }
  end

  def assign_sheet_stock_sort_orders!(project)
    project.sheet_stocks.reject(&:marked_for_destruction?).each_with_index do |stock, index|
      stock.sort_order = index
    end
  end
end
