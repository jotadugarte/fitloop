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

      payment = pending_single_download_payments(user: user)
                .order(created_at: :desc)
                .detect { |candidate| new(payment: candidate).active? }
      return nil if payment.nil?

      new(payment: payment)
    end

    def self.pending_payment_for(project:, user:)
      return nil if project.nil? || user.nil?

      pending_single_download_payments(user: user)
        .joins(:nesting_run)
        .where(nesting_runs: { project_id: project.id })
        .order(created_at: :desc)
        .detect { |candidate| new(payment: candidate).active? }
    end

    def self.pending_single_download_payments(user:)
      Payment.pending.single_download.where(user_id: user.id)
    end

    def initialize(payment:)
      @payment = payment
    end

    def active?
      return false unless @payment.pending?
      return false if superseded_by_successful_checkout?

      grant = DownloadGrant.single_purchase.find_by(
        user_id: @payment.user_id,
        nesting_run_id: @payment.nesting_run_id
      )
      return true if grant.nil?

      !(grant.updated_at >= @payment.created_at && grant.retention_active?)
    end

    def superseded_by_successful_checkout?
      Payment.succeeded.single_download
             .where(user_id: @payment.user_id, nesting_run_id: @payment.nesting_run_id)
             .where("created_at >= ?", @payment.created_at)
             .exists?
    end

    private :superseded_by_successful_checkout?

    def payment_id
      @payment.id
    end

    def message
      I18n.t("billing.checkout.pending_workshop_lock.message")
    end
  end
end
