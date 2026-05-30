# frozen_string_literal: true

# [REQ-FIT-BILL-001] Prevent sheet/nest changes while ONVO checkout is still pending.
module BlocksWorkshopDuringPendingPayment
  extend ActiveSupport::Concern

  private

  def pending_checkout_lock
    return @pending_checkout_lock if defined?(@pending_checkout_lock)

    @pending_checkout_lock = Billing::PendingCheckoutLock.for(project: @project, user: current_user)
  end

  def workshop_mutations_locked?
    pending_checkout_lock&.active?
  end

  def reject_workshop_mutation_if_pending_payment!
    lock = pending_checkout_lock
    return false unless lock&.active?

    respond_to_pending_payment_lock!(lock)
    true
  end

  def respond_to_pending_payment_lock!(lock)
    message = lock.message

    if (request.format.turbo_stream? || params[:section].present?) && respond_to?(:render_workspace_turbo_stream, true)
      flash.now[:alert] = message
      section = params[:section].to_s == "layers" ? :layers : :sheets
      render_workspace_turbo_stream(section, status: :unprocessable_content)
      return
    end

    redirect_to workshop_path, alert: message
  end
end
