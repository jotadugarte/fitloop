# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] [REQ-FIT-BILL-003] Grant entitlements after confirmed payment.
  class FulfillPayment
    def self.call(payment:)
      new(payment: payment).call
    end

    def initialize(payment:)
      @payment = payment
    end

    def call
      raise ArgumentError, "payment required" if @payment.nil?
      return :already_fulfilled if @payment.succeeded?

      case @payment.purpose
      when "single_download"
        fulfill_single_download!
      else
        raise ArgumentError, "unsupported payment purpose: #{@payment.purpose}"
      end
    end

    private

    def fulfill_single_download!
      nesting_run = @payment.nesting_run
      raise ArgumentError, "nesting_run required" if nesting_run.nil?

      paid_at = Time.current
      ActiveRecord::Base.transaction do
        @payment.update!(
          status: :succeeded,
          paid_at: paid_at,
          gateway_status: Payment::ONVO_GATEWAY_SUCCEEDED
        )
        grant = DownloadGrant.find_or_initialize_by(
          user_id: @payment.user_id,
          nesting_run_id: nesting_run.id
        )
        unless grant.persisted? && grant.retention_active?
          grant.kind = :single_purchase
          grant.retained_until = paid_at + RetainNestedDxf::RETENTION_HOURS.hours
          grant.save!
          RetainNestedDxf.call(grant: grant, nesting_run: nesting_run, paid_at: paid_at)
        end
      end
      :fulfilled
    end
  end
end
