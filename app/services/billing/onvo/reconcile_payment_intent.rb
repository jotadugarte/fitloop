# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Sync local Payment gateway_status from ONVO after 3DS return.
    class ReconcilePaymentIntent
      def self.call(payment:, client: nil)
        new(payment: payment, client: client).call
      end

      def initialize(payment:, client: nil)
        @payment = payment
        @client = client
      end

      def call
        raise ArgumentError, "payment required" if @payment.nil?
        raise ArgumentError, "ONVO intent required" if @payment.onvo_payment_intent_id.blank?

        intent = onvo_client.get_payment_intent(@payment.onvo_payment_intent_id)
        status = intent.fetch(:status).to_s
        @payment.update!(gateway_status: status)
        intent
      end

      private

      def onvo_client
        @client ||= Client.from_env
      end
    end
  end
end
