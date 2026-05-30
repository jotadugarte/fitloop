# frozen_string_literal: true

module Billing
  module MisPagos
    # [REQ-FIT-BILL-001] [REQ-FIT-BILL-002] Merges retained grants and pending single-download payments.
    class SinglePurchaseRows
      Row = Data.define(:sort_at, :grant, :pending_payment, :nesting_run, :display_payment) do
        def pending?
          pending_payment.present?
        end

        def pending_lock_active?
          pending? && pending_payment.checkout_lock_active?
        end

        def pending_lock_expired?
          pending? && !pending_lock_active? && pending_payment.awaiting_gateway_confirmation?
        end

        def pending_cancelable?
          pending? && !pending_payment.checkout_abandoned?
        end

        def downloadable?
          grant.present? && grant.retention_active?
        end

        def payment_for_display
          pending_payment || display_payment
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
                      .includes(nesting_run: :project)
                      .order(created_at: :desc)
                      .select { |grant| grant.retention_active? && !pending_run_ids.include?(grant.nesting_run_id) }

        run_ids = (grants.map(&:nesting_run_id) + pending.map(&:nesting_run_id)).compact.uniq
        succeeded_by_run = succeeded_payments_by_run(run_ids)

        rows = grant_rows(grants, succeeded_by_run) + pending_rows(pending)
        rows.sort_by(&:sort_at).reverse
      end

      private

      def awaiting_pending_payments
        PendingCheckoutLock.pending_single_download_payments(user: @user)
                           .where(superseded_at: nil)
                           .includes(nesting_run: :project)
                           .order(created_at: :desc)
                           .select(&:awaiting_gateway_confirmation?)
      end

      def succeeded_payments_by_run(run_ids)
        return {} if run_ids.empty?

        Payment.succeeded.single_download
               .where(user_id: @user.id, nesting_run_id: run_ids)
               .order(created_at: :desc)
               .group_by(&:nesting_run_id)
               .transform_values(&:first)
      end

      def grant_rows(grants, succeeded_by_run)
        grants.map do |grant|
          Row.new(
            sort_at: grant.created_at,
            grant: grant,
            pending_payment: nil,
            nesting_run: grant.nesting_run,
            display_payment: succeeded_by_run[grant.nesting_run_id]
          )
        end
      end

      def pending_rows(payments)
        payments.map do |payment|
          Row.new(
            sort_at: payment.created_at,
            grant: nil,
            pending_payment: payment,
            nesting_run: payment.nesting_run,
            display_payment: nil
          )
        end
      end
    end
  end
end
