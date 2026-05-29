# frozen_string_literal: true

# [REQ-FIT-BILL-002] Payment history and retained downloads (D38).
class MisPagosController < ApplicationController
  include RequiresBillingConfirmation

  def show
    flash.now[:notice] = t("billing.checkout.success_retention") if params[:payment_succeeded].present?

    @subscription = Subscription.active_at.find_by(user_id: current_user.id)
    @quota_counter = Billing::QuotaCounter.for(@subscription) if @subscription
    @payments = current_user.payments.order(created_at: :desc).limit(100)
    @pending_checkout_lock = Billing::PendingCheckoutLock.for_user(user: current_user)
    @retained_grants = current_user.download_grants.single_purchase.order(created_at: :desc)
    @auto_download_grant = auto_download_grant
  end

  private

  def auto_download_grant
    return unless params[:auto_download].present?

    grant = current_user.download_grants.single_purchase.find_by(id: params[:auto_download])
    grant if grant&.retention_active?
  end
end
