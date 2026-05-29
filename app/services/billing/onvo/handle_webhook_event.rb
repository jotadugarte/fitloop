# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Routes ONVO webhook events to billing fulfillment services.
    class HandleWebhookEvent
      class PaymentNotFound < StandardError; end

      def self.call(payload:)
        new(payload: payload).call
      end

      def initialize(payload:)
        @event = WebhookEvent.new(payload)
      end

      def call
        payment = find_payment!
        dispatch_for(payment)
      end

      private

      def find_payment!
        Payment.find_by(onvo_payment_intent_id: @event.payment_intent_id) ||
          raise(PaymentNotFound, "payment not found for intent #{@event.payment_intent_id}")
      end

      def dispatch_for(payment)
        case @event.type
        when "payment-intent.succeeded"
          Billing::FulfillPayment.call(payment: payment)
        when "payment-intent.failed"
          Billing::FailPayment.call(payment: payment)
        else
          :ignored
        end
      end
    end
  end
end
