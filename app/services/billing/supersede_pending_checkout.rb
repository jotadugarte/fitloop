# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Marks prior pending SINPE single-download attempts superseded before a new checkout.
  class SupersedePendingCheckout
    REASON = CheckoutLockReason::SUPERSEDED
    MAX_PENDING_PER_RUN = 8

    def self.call(user:, nesting_run:)
      new(user: user, nesting_run: nesting_run).call
    end

    def initialize(user:, nesting_run:)
      @user = user
      @nesting_run = nesting_run
    end

    def call
      raise ArgumentError, "user required" if @user.nil?
      return 0 if @nesting_run.nil?

      count = 0
      pending_candidates.each do |payment|
        mark_superseded!(payment)
        count += 1
      end
      count
    end

    private

    def pending_candidates
      Payment.pending.single_download.sinpe_crc
             .where(user_id: @user.id, nesting_run_id: @nesting_run.id, superseded_at: nil)
             .order(created_at: :asc)
             .limit(MAX_PENDING_PER_RUN)
             .to_a
    end

    def mark_superseded!(payment)
      return if payment.superseded_at.present?

      now = Time.current
      payment.update!(
        superseded_at: now,
        checkout_lock_released_at: now,
        checkout_lock_reason: REASON
      )
    end
  end
end
