# frozen_string_literal: true

# [REQ-FIT-BILL-001] Single-run simulated checkout (D37).
class CheckoutController < ApplicationController
  include RequiresBillingConfirmation
  include ResolvesWorkspaceTab

  before_action :load_checkout_context, only: %i[show simulate]
  before_action :reject_checkout_when_plan_quota_available!, only: %i[show simulate]

  def show
    @billing_geo_defaults = Billing::GeoPaymentDefaults.from_request(request)
    @available_payment_methods = @billing_geo_defaults.fetch(:available_payment_methods)
    render :show
  end

  def simulate
    result = Billing::SimulateSingleDownload.call(
      user: current_user,
      nesting_run: @nesting_run,
      payment_method: params[:payment_method],
      outcome: params[:outcome]
    )
    if result == :failed
      redirect_to checkout_path(nesting_run_id: @nesting_run.id), alert: t("billing.checkout.failure")
      return
    end

    redirect_to mis_pagos_path(auto_download: result[:grant].id),
                notice: t("billing.checkout.success_retention")
  end

  private

  def load_checkout_context
    @nesting_run = NestingRun.find_by(id: params[:nesting_run_id])
    return redirect_to(start_project_path, alert: t("workspace.expired")) unless @nesting_run

    @project = @nesting_run.project
    return if Workspace.bound_to_project?(session, @project)

    redirect_to start_project_path, alert: t("workspace.expired")
  end

  def reject_checkout_when_plan_quota_available!
    return if Billing::PlanDownloadAvailability.single_download_checkout_allowed?(user: current_user)

    redirect_to project_path(@project), notice: t("billing.checkout.plan_quota_prioritized")
  end
end
