# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Creates an ONVO payment intent from CheckoutBreakdown and links Payment.
    class CreatePaymentIntent
      def self.call(payment:, breakdown:, client: nil, description: nil)
        new(payment: payment, breakdown: breakdown, client: client, description: description).call
      end

      def initialize(payment:, breakdown:, client: nil, description: nil)
        @payment = payment
        @breakdown = breakdown
        @client = client
        @description = description
      end

      def call
        raise ArgumentError, "payment must be persisted" unless @payment.persisted?
        raise ArgumentError, "breakdown required" if @breakdown.nil?

        minor = MoneyMinorUnits.from_breakdown(@breakdown)
        response = onvo_client.create_payment_intent(
          amount: minor.to_i,
          currency: minor.currency_code,
          description: intent_description,
          metadata: { payment_id: @payment.id.to_s }
        )

        persist_gateway_fields!(response)
        response
      end

      private

      def onvo_client
        @client ||= Client.from_env
      end

      def intent_description
        @description.presence || "Fitloop payment ##{@payment.id}"
      end

      def persist_gateway_fields!(response)
        @payment.update!(
          gateway_provider: :onvo,
          onvo_payment_intent_id: response.fetch(:id),
          onvo_mode: onvo_client.mode,
          gateway_status: response.fetch(:status)
        )
      end
    end
  end
end
