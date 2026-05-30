# frozen_string_literal: true

module Billing
  module MisPagos
    # [REQ-FIT-BILL-001] [REQ-FIT-BILL-002] Merges retained grants and pending single-download payments.
    class SinglePurchaseRows
      Row = Data.define(:sort_at, :grant, :pending_payment) do
        def pending?
          pending_payment.present?
        end

        def pending_lock_active?
          pending? && pending_payment.checkout_lock_active?
        end

        def pending_lock_expired?
          pending? && !pending_lock_active? && pending_payment.awaiting_gateway_confirmation?
        end

        def downloadable?
          grant.present? && grant.retention_active?
        end
      end

      def self.build(user:)
        new(user: user).build
      end

      def initialize(user:)
        @user = user
      end

      def build
        pending = awaiting_pending_payments
        pending_run_ids = pending.map(&:nesting_run_id).compact.to_set
        grants = @user.download_grants.single_purchase
                      .order(created_at: :desc)
                      .select { |grant| grant.retention_active? && !pending_run_ids.include?(grant.nesting_run_id) }

        rows = grant_rows(grants) + pending_rows(pending)
        rows.sort_by(&:sort_at).reverse
      end

      private

      def awaiting_pending_payments
        PendingCheckoutLock.pending_single_download_payments(user: @user)
                           .where(superseded_at: nil)
                           .order(created_at: :desc)
                           .select(&:awaiting_gateway_confirmation?)
      end

      def grant_rows(grants)
        grants.map { |grant| Row.new(sort_at: grant.created_at, grant: grant, pending_payment: nil) }
      end

      def pending_rows(payments)
        payments.map do |payment|
          Row.new(sort_at: payment.created_at, grant: nil, pending_payment: payment)
        end
      end
    end
  end
end
