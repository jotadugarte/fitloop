# frozen_string_literal: true

# [REQ-FIT-JOB-001] Start and cancel nesting jobs for a project.
class NestingRunsController < ApplicationController
  before_action :set_project

  def create
    readiness = ProjectReadinessValidator.validate(@project)
    unless readiness.ok?
      redirect_to @project, alert: readiness.errors.join(" ")
      return
    end

    nesting_run = @project.nesting_runs.create!(status: "processing", params_snapshot: {})
    @project.update!(
      status: :processing,
      progress_percent: 0,
      progress_message: I18n.t("nesting.queued"),
      estimated_finished_at: Time.current + 30.seconds
    )
    NestingJob.perform_later(nesting_run.id)
    notice = renest? ? I18n.t("nesting.renest_started") : I18n.t("nesting.started")
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

  def renest?
    @project.nested_dxf.attached? && (@project.completed? || @project.partial?)
  end
end
