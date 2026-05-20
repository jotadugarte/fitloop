# frozen_string_literal: true

# [REQ-FIT-JOB-001] Start and cancel nesting jobs for a project.
class NestingRunsController < ApplicationController
  include StartsNesting
  include SetsWorkspaceProject

  before_action :set_workspace_project

  def create
    @project.reload
    SheetStocks::NormalizeConsumptionOrder.call(@project)
    SheetStocks::NormalizeConsumptionOrder.persist!(@project)
    readiness = ProjectReadinessValidator.validate(@project)
    unless readiness.ok?
      redirect_to @project, alert: readiness.errors.join(" ")
      return
    end

    nest_updated_pieces = ActiveModel::Type::Boolean.new.cast(params[:nest_updated_pieces])
    if nest_updated_pieces && @project.derived_pieces.none?
      redirect_to @project, alert: I18n.t("nesting.nest_updated_pieces_unavailable")
      return
    end

    start_nesting_for!(@project, nest_updated_pieces: nest_updated_pieces)
    redirect_to @project
  end

  def cancel
    nesting_run = @project.nesting_runs.order(created_at: :desc).find(params[:id])
    nesting_run.update!(cancel_requested_at: Time.current)
    redirect_to @project, notice: I18n.t("nesting.cancelling")
  end

end
