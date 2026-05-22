# frozen_string_literal: true

# [REQ-FIT-BILL-002] Plan pricing and simulated checkout (D37, D43).
class PlanesController < ApplicationController
  include RequiresBillingConfirmation
  include ResolvesWorkspaceTab

  before_action :load_plan_project!, only: %i[show simulate]

  def show
  end

  def simulate
    unless current_user.operationally_active?
      redirect_to edit_user_registration_path, alert: t("billing.suspended")
      return
    end

    unless @project
      redirect_to planes_path, alert: t("billing.planes.project_required")
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

    redirect_to workshop_path, notice: t("billing.planes.success")
  end

  private

  def load_plan_project!
    return unless params[:project_id].present?

    @project = Project.find_by(id: params[:project_id])
    unless @project
      redirect_to start_project_path, alert: t("workspace.expired")
      return
    end

    return if Workspace.bound_to_project?(session, @project)

    redirect_to start_project_path, alert: t("workspace.expired")
  end
end
