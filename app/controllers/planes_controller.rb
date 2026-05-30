# frozen_string_literal: true

# [REQ-FIT-BILL-002] Plan pricing and simulated checkout (D37, D43).
class PlanesController < ApplicationController
  include RequiresBillingConfirmation
  include ResolvesWorkspaceTab

  before_action :load_plan_project!, only: %i[show simulate]
  before_action :redirect_to_cart_if_cart_item_present!, only: :show

  def show
    @active_subscription = Subscription.active_at.find_by(user_id: current_user.id)
  end

  def simulate
    unless current_user.operationally_active?
      redirect_to edit_user_registration_path, alert: t("billing.suspended")
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

    redirect_after_plan_purchase!
  rescue ArgumentError
    redirect_to planes_path(project_id: @project&.id), alert: t("billing.checkout.failure")
  end

  private

  def redirect_after_plan_purchase!
    if @project && Workspace.bound_to_project?(session, @project)
      redirect_to workshop_path, notice: t("billing.planes.success")
      return
    end

    redirect_to mis_pagos_path, notice: t("billing.planes.success")
  end

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

  def redirect_to_cart_if_cart_item_present!
    return unless Cart.exists?(user_id: current_user.id)

    redirect_to checkout_path
  end
end
