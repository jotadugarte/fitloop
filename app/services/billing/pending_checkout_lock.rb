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

      payment = Payment.pending.single_download
                       .where(user_id: user.id)
                       .order(created_at: :desc)
                       .first
      return nil if payment.nil?

      new(payment: payment)
    end

    def self.pending_payment_for(project:, user:)
      return nil if project.nil? || user.nil?

      Payment.pending.single_download
             .where(user_id: user.id)
             .joins(:nesting_run)
             .find_by(nesting_runs: { project_id: project.id })
    end

    def initialize(payment:)
      @payment = payment
    end

    def active?
      @payment.pending?
    end

    def payment_id
      @payment.id
    end

    def message
      I18n.t("billing.checkout.pending_workshop_lock.message")
    end
  end
end
