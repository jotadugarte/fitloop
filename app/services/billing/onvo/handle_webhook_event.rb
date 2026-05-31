# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Routes ONVO webhook events to billing fulfillment services.
    class HandleWebhookEvent
      class PaymentNotFound < StandardError; end

      def self.call(payload:, request: nil)
        new(payload: payload, request: request).call
      end

      def initialize(payload:, request: nil)
        @event = WebhookEvent.new(payload)
        @request = request
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

      def abandon_incomplete_card_webhook?(payment)
        return true if payment.checkout_abandoned_at.present?

        payment.incomplete_card_checkout_attempt?
      end

      def abandon_incomplete_card_instead!(payment)
        Billing::AbandonIncompleteCardCheckout.call(payment: payment)
        :abandoned
      end

      def dispatch_for(payment)
        case @event.type
        when "payment-intent.succeeded"
          Billing::FulfillPayment.call(payment: payment, request: @request)
        when "payment-intent.failed"
          return abandon_incomplete_card_instead!(payment) if abandon_incomplete_card_webhook?(payment)

          Billing::FailPayment.call(payment: payment, request: @request)
        else
          :ignored
        end
      end
    end
  end
end
