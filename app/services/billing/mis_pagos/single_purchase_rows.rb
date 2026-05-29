# frozen_string_literal: true

module Billing
  module MisPagos
    # [REQ-FIT-BILL-001] [REQ-FIT-BILL-002] Merges retained grants and pending single-download payments.
    class SinglePurchaseRows
      Row = Data.define(:sort_at, :grant, :pending_payment) do
        def pending?
          pending_payment.present?
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
        grants = @user.download_grants.single_purchase.order(created_at: :desc).to_a
        covered_run_ids = grants.map(&:nesting_run_id).compact.to_set
        pending = pending_payments_excluding(covered_run_ids)

        rows = grant_rows(grants) + pending_rows(pending)
        rows.sort_by(&:sort_at).reverse
      end

      private

      def grant_rows(grants)
        grants.map { |grant| Row.new(sort_at: grant.created_at, grant: grant, pending_payment: nil) }
      end

      def pending_rows(payments)
        payments.map do |payment|
          Row.new(sort_at: payment.created_at, grant: nil, pending_payment: payment)
        end
      end

      def pending_payments_excluding(covered_run_ids)
        Payment.pending.single_download
               .where(user_id: @user.id)
               .order(created_at: :desc)
               .includes(:nesting_run)
               .reject { |payment| covered_run_ids.include?(payment.nesting_run_id) }
      end
    end
  end
end
