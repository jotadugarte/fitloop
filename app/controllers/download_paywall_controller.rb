# frozen_string_literal: true

# [REQ-FIT-BILL-001] Paywall before nested DXF download (D42).
class DownloadPaywallController < ApplicationController
  include SetsWorkspaceProject
  include BlocksWorkshopDuringPendingPayment

  before_action :set_workspace_project
  before_action :reject_workshop_mutation_if_pending_payment!
  before_action :store_guest_paywall_return_to!, only: :show

  def show
    @billing_geo_defaults = Billing::GeoPaymentDefaults.from_request(request, session: session, user: current_user)
    @available_payment_methods = @billing_geo_defaults.fetch(:available_payment_methods)
    @billing_selection = Billing::PaymentSelection.resolve(request: request, session: session, user: current_user)
    @nesting_run = @project.nesting_runs
                           .where(status: Nesting::StatusMapper::DOWNLOADABLE_RUN_STATUSES)
                           .order(id: :desc)
                           .first
    @plan_download_included = Billing::PlanDownloadAvailability.plan_included?(user: current_user)
    @single_download_checkout_allowed =
      Billing::PlanDownloadAvailability.single_download_checkout_allowed?(user: current_user)

    Analytics::TrackEvent.call(
      "paywall_viewed",
      user_id: current_user&.id,
      anonymous_session_key: session[:anonymous_session_key],
      tab_id: workspace_tab_id,
      project_id: @project&.id,
      ip: request.remote_ip,
      user_agent: request.user_agent,
      country_code: Analytics::ResolveCountry.call(request),
      locale: I18n.locale.to_s
    )
  end

  private

  # For /taller/descarga-pago we want a stable destination even when the user
  # arrives without an existing workshop bind (e.g. from home → mis-pagos).
  # Create/bind an ephemeral workspace instead of redirecting to /projects/new.
  def set_workspace_project
    return if expire_workspace_after_tab_closure!

    if missing_tab_id_for_bound_workspaces?
      redirect_to start_project_path, alert: I18n.t("workspace.expired")
      return
    end

    @project = Workspace.find_or_create!(session, tab_id: workspace_tab_id, request: request)

    nil if performed?
  end

  def store_guest_paywall_return_to!
    return if user_signed_in?

    session[:workspace_return_to] = download_paywall_workshop_path
  end
end
