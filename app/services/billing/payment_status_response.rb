# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] JSON payload for checkout payment status polling.
  class PaymentStatusResponse
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
        redirect_url: redirect_url_if_ready
      }
    end

    private

    def redirect_url_if_ready
      return nil unless @payment.succeeded?

      if @payment.single_download?
        grant = DownloadGrant.find_by(user_id: @payment.user_id, nesting_run_id: @payment.nesting_run_id)
        return @routes.mis_pagos_path(auto_download: grant.id) if grant

        return @routes.mis_pagos_path
      end

      @routes.mis_pagos_path if @payment.plan_subscription?
    end
  end
end
