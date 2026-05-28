# frozen_string_literal: true

# [REQ-FIT-BILL-001] Paywall before nested DXF download (D42).
class DownloadPaywallController < ApplicationController
  include SetsWorkspaceProject

  before_action :set_workspace_project
  before_action :store_guest_paywall_return_to!, only: :show

  def show
    @billing_selection = Billing::PaymentSelection.resolve(request: request, session: session)
    @nesting_run = @project.nesting_runs
                           .where(status: Nesting::StatusMapper::DOWNLOADABLE_RUN_STATUSES)
                           .order(id: :desc)
                           .first
    @plan_download_included = Billing::PlanDownloadAvailability.plan_included?(user: current_user)
    @single_download_checkout_allowed =
      Billing::PlanDownloadAvailability.single_download_checkout_allowed?(user: current_user)
  end

  private

  def store_guest_paywall_return_to!
    return if user_signed_in?

    session[:workspace_return_to] = download_paywall_workshop_path
  end
end
