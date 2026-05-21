# frozen_string_literal: true

# [REQ-FIT-AUTH-002] Checkout routes require verified email (D22).
module RequiresBillingConfirmation
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user!
    before_action :require_confirmed_for_checkout!
  end

  private

  def require_confirmed_for_checkout!
    precondition!(current_user.present?)
    return if current_user.billing_ready?

    redirect_to "/confirmacion", alert: t("devise.failure.unconfirmed")
  end

  def precondition!(condition)
    raise ArgumentError, "precondition failed" unless condition
  end
end
