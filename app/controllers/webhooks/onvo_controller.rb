# frozen_string_literal: true

module Webhooks
  # [REQ-FIT-BILL-001] ONVO payment webhooks (CSRF skipped; secret header required).
  class OnvoController < ActionController::Base
    skip_before_action :verify_authenticity_token

    def create
      unless Billing::Onvo::VerifyWebhook.call(request: request)
        head :unauthorized
        return
      end

      res = Billing::Onvo::HandleWebhookEvent.call(payload: webhook_payload, request: request)
      if res == :already_fulfilled
        render json: { status: :already_fulfilled }, status: :ok
      else
        head :ok
      end
    rescue Billing::Onvo::HandleWebhookEvent::PaymentNotFound
      head :not_found
    end

    private

    def webhook_payload
      body = request.body.read
      return {} if body.blank?

      JSON.parse(body)
    end
  end
end
