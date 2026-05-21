# frozen_string_literal: true

# [REQ-FIT-BILL-002] Payment history and retained downloads (D38).
class MisPagosController < ApplicationController
  include RequiresBillingConfirmation

  def show
    @subscription = Subscription.active_at.find_by(user_id: current_user.id)
    @quota_counter = Billing::QuotaCounter.for(@subscription) if @subscription
    @payments = current_user.payments.order(created_at: :desc).limit(100)
    @retained_grants = current_user.download_grants.single_purchase.order(created_at: :desc)
  end
end
