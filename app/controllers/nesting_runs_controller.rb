# frozen_string_literal: true

# [REQ-FIT-JOB-001] Start and cancel nesting jobs for a project.
class NestingRunsController < ApplicationController
  include StartsNesting
  include SetsWorkspaceProject

  before_action :set_workspace_project
  before_action -> { require_project_access!(@project) }

  def create
    @project.reload
    SheetStocks::NormalizeConsumptionOrder.call(@project)
    SheetStocks::NormalizeConsumptionOrder.persist!(@project)
    readiness = ProjectReadinessValidator.validate(@project)
    unless readiness.ok?
      redirect_to @project, alert: readiness.errors.join(" ")
      return
    end

    start_nesting_for!(@project)
    redirect_to @project
  end

  def cancel
    nesting_run = @project.nesting_runs.order(created_at: :desc).find(params[:id])
    nesting_run.update!(cancel_requested_at: Time.current)
    redirect_to @project, notice: I18n.t("nesting.cancelling")
  end

end
