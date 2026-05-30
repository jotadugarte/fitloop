# frozen_string_literal: true

# [REQ-FIT-BILL-002] Payment history and retained downloads (D38).
class MisPagosController < ApplicationController
  include RequiresBillingConfirmation

  def show
    flash.now[:notice] = t("billing.checkout.success_retention") if params[:payment_succeeded].present?

    @subscription = Subscription.active_at.find_by(user_id: current_user.id)
    @quota_counter = Billing::QuotaCounter.for(@subscription) if @subscription
    @payments = current_user.payments.listed_in_payment_history.order(created_at: :desc).limit(100)
    @pending_checkout_lock = Billing::PendingCheckoutLock.for_user(user: current_user)
    @single_purchase_rows = Billing::MisPagos::SinglePurchaseRows.build(user: current_user)
    @downloads_ready_count = @single_purchase_rows.count(&:downloadable?)
    @downloads_pending_count = @single_purchase_rows.count(&:pending?)
    @pending_payment_for_poll = pending_payment_for_poll
    @pending_payment_status_url = checkout_payment_status_path(@pending_payment_for_poll) if @pending_payment_for_poll
    @auto_download_grant = auto_download_grant
  end

  private

  def pending_payment_for_poll
    Payment.pending.single_download
           .where(user_id: current_user.id, superseded_at: nil)
           .order(created_at: :desc)
           .detect(&:awaiting_gateway_confirmation?)
  end

  def auto_download_grant
    return unless params[:auto_download].present?

    grant = current_user.download_grants.single_purchase.find_by(id: params[:auto_download])
    grant if grant&.retention_active?
  end
end
