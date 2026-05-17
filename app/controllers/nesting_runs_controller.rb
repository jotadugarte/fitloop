# frozen_string_literal: true

# [REQ-FIT-JOB-001] Start and cancel nesting jobs for a project.
class NestingRunsController < ApplicationController
  include StartsNesting

  before_action :set_project
  before_action -> { require_project_access!(@project) }

  def create
    readiness = ProjectReadinessValidator.validate(@project)
    unless readiness.ok?
      redirect_to @project, alert: readiness.errors.join(" ")
      return
    end

    renesting = renesting?(@project)
    start_nesting_for!(@project)
    notice = renesting ? I18n.t("nesting.renest_started") : I18n.t("nesting.started")
    redirect_to @project, notice: notice
  end

  def cancel
    nesting_run = @project.nesting_runs.order(created_at: :desc).find(params[:id])
    nesting_run.update!(cancel_requested_at: Time.current)
    redirect_to @project, notice: I18n.t("nesting.cancelling")
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

end
