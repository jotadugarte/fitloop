# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Blocks workshop mutations while a single-download checkout is pending.
  class PendingCheckoutLock
    def self.for(project:, user:)
      payment = pending_payment_for(project: project, user: user)
      return nil if payment.nil?

      new(payment: payment)
    end

    def self.for_user(user:)
      return nil if user.nil?

      payment = unfulfilled_pending_payments(user: user).order(created_at: :desc).first
      return nil if payment.nil?

      new(payment: payment)
    end

    def self.pending_payment_for(project:, user:)
      return nil if project.nil? || user.nil?

      unfulfilled_pending_payments(user: user)
        .joins(:nesting_run)
        .where(nesting_runs: { project_id: project.id })
        .order(created_at: :desc)
        .first
    end

    def self.unfulfilled_pending_payments(user:)
      granted_run_ids = DownloadGrant.single_purchase.where(user_id: user.id).select(:nesting_run_id)

      Payment.pending.single_download.where(user_id: user.id).where.not(nesting_run_id: granted_run_ids)
    end

    def initialize(payment:)
      @payment = payment
    end

    def active?
      return false unless @payment.pending?

      !DownloadGrant.single_purchase.exists?(
        user_id: @payment.user_id,
        nesting_run_id: @payment.nesting_run_id
      )
    end

    def payment_id
      @payment.id
    end

    def message
      I18n.t("billing.checkout.pending_workshop_lock.message")
    end
  end
end
