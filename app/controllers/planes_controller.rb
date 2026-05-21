# frozen_string_literal: true

# [REQ-FIT-BILL-002] Plan pricing and simulated checkout (D37, D43).
class PlanesController < ApplicationController
  include RequiresBillingConfirmation
  include ResolvesWorkspaceTab

  before_action :load_plan_context, only: %i[simulate]

  def show
    @project = Project.find_by(id: params[:project_id])
    render :show
  end

  def simulate
    unless current_user.operationally_active?
      redirect_to "/mi-cuenta", alert: t("billing.suspended")
      return
    end

    result = Billing::SimulatePlanPurchase.call(
      user: current_user,
      tier_months: params[:tier_months],
      payment_method: params[:payment_method],
      outcome: params[:outcome],
      project: @project
    )
    if result == :failed
      redirect_to planes_path(project_id: @project.id), alert: t("billing.checkout.failure")
      return
    end

    redirect_to project_path(@project), notice: t("billing.planes.success")
  end

  private

  def load_plan_context
    @project = Project.find_by(id: params[:project_id])
    return redirect_to(start_project_path, alert: t("workspace.expired")) unless @project

    bound = Workspace.find(session, tab_id: workspace_tab_id)
    return if bound&.id == @project.id

    redirect_to start_project_path, alert: t("workspace.expired")
  end
end
