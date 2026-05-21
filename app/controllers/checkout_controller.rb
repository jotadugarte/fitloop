# frozen_string_literal: true

# [REQ-FIT-BILL-001] Single-run simulated checkout (D37).
class CheckoutController < ApplicationController
  include RequiresBillingConfirmation
  include ResolvesWorkspaceTab

  before_action :load_checkout_context, only: %i[show simulate]

  def show
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

    token = Billing::DownloadToken.issue(user: current_user, nesting_run: @nesting_run)
    redirect_to nested_dxf_project_path(
      result[:project],
      download_token: token
    ), notice: t("billing.checkout.success_retention")
  end

  private

  def load_checkout_context
    @nesting_run = NestingRun.find_by(id: params[:nesting_run_id])
    return redirect_to(start_project_path, alert: t("workspace.expired")) unless @nesting_run

    @project = @nesting_run.project
    bound = Workspace.find(session, tab_id: workspace_tab_id)
    return if bound&.id == @project.id

    redirect_to start_project_path, alert: t("workspace.expired")
  end
end
