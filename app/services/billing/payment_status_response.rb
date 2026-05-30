# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] JSON payload for checkout payment status polling.
  class PaymentStatusResponse
    DECLINED_GATEWAY_STATUSES = %w[requires_payment_method].freeze
    ABANDONED_GATEWAY_STATUSES = %w[requires_action canceled].freeze

    def self.for(payment:, routes:)
      new(payment: payment, routes: routes).to_h
    end

    def initialize(payment:, routes:)
      @payment = payment
      @routes = routes
    end

    def to_h
      {
        status: @payment.status,
        gateway_status: @payment.gateway_status,
        redirect_url: redirect_url_if_ready,
        checkout_return_url: checkout_return_url_if_abandoned,
        checkout_failed_url: checkout_failed_url_if_failed,
        checkout_lock_active: @payment.checkout_lock_active?,
        checkout_lock_expired: checkout_lock_expired?,
        release_pending_url: release_pending_url_if_applicable,
        retry_checkout_url: retry_checkout_url_if_applicable
      }
    end

    private

    def redirect_url_if_ready
      return nil unless @payment.succeeded?
      return nil unless @payment.gateway_status.to_s == "succeeded"

      if @payment.single_download?
        grant = DownloadGrant.find_by(user_id: @payment.user_id, nesting_run_id: @payment.nesting_run_id)
        return mis_pagos_success_url(auto_download: grant.id) if grant

        return nil
      end

      mis_pagos_success_url if @payment.plan_subscription?
    end

    def mis_pagos_success_url(**params)
      @routes.mis_pagos_path(params.merge(payment_succeeded: 1))
    end

    def checkout_return_url_if_abandoned
      return nil if @payment.succeeded? || @payment.failed?
      return @routes.checkout_payment_failed_path(@payment) if declined_gateway_status?

      return nil unless ABANDONED_GATEWAY_STATUSES.include?(@payment.gateway_status.to_s)

      @routes.checkout_payment_canceled_path(@payment)
    end

    def declined_gateway_status?
      DECLINED_GATEWAY_STATUSES.include?(@payment.gateway_status.to_s)
    end

    def checkout_failed_url_if_failed
      return nil unless @payment.failed?

      @routes.checkout_payment_failed_path(@payment)
    end

    def checkout_lock_expired?
      @payment.pending? && @payment.checkout_lock_expired?
    end

    def release_pending_url_if_applicable
      return nil unless @payment.sinpe_crc? && @payment.pending? && @payment.checkout_lock_active?

      @routes.checkout_release_pending_lock_path(@payment)
    end

    def retry_checkout_url_if_applicable
      return nil unless @payment.sinpe_crc?
      return nil unless @payment.single_download? && @payment.nesting_run_id.present?
      return nil unless @payment.pending? && !@payment.checkout_lock_active?

      @routes.checkout_path(nesting_run_id: @payment.nesting_run_id)
    end
  end
end
