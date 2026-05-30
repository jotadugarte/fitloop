# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Tokenize card and confirm intent (card-only; no ONVO SDK widget).
    class ConfirmCardPayment
      def self.call(payment:, holder_name:, card_number:, exp_month:, exp_year:, cvv:, return_url:, client: nil)
        new(
          payment: payment,
          holder_name: holder_name,
          card_number: card_number,
          exp_month: exp_month,
          exp_year: exp_year,
          cvv: cvv,
          return_url: return_url,
          client: client
        ).call
      end

      def initialize(payment:, holder_name:, card_number:, exp_month:, exp_year:, cvv:, return_url:, client: nil)
        @payment = payment
        @holder_name = holder_name
        @card_number = card_number.to_s.gsub(/[\s-]/, "")
        @exp_month = exp_month
        @exp_year = exp_year
        @cvv = cvv
        @return_url = return_url.to_s.strip
        @client = client
      end

      def call
        raise ArgumentError, "payment required" if @payment.nil?
        raise ArgumentError, "ONVO intent required" if @payment.onvo_payment_intent_id.blank?
        raise ArgumentError, "card payment required" unless card_payment?

        method = onvo_client.create_payment_method(
          type: "card",
          card: {
            number: @card_number,
            expMonth: @exp_month,
            expYear: @exp_year,
            cvv: @cvv,
            holderName: @holder_name
          },
          billing: billing_payload
        )

        intent = onvo_client.confirm_payment_intent(
          @payment.onvo_payment_intent_id,
          payment_method_id: method.fetch(:id),
          return_url: @return_url.presence
        )

        @payment.update!(gateway_status: intent.fetch(:status))

        {
          payment_id: @payment.id,
          status: intent.fetch(:status),
          redirect_url: three_ds_redirect_url(intent)
        }
      end

      private

      def card_payment?
        @payment.payment_method.to_s.start_with?("card")
      end

      def billing_payload
        {
          name: @holder_name,
          email: @payment.purchaser_email.presence || @payment.user.email,
          address: { country: billing_country }
        }
      end

      def billing_country
        @payment.currency.to_s == "usd" ? "US" : "CR"
      end

      def three_ds_redirect_url(intent)
        return nil unless intent.fetch(:status).to_s == "requires_action"

        intent.dig(:nextAction, :redirectToUrl, :url) ||
          intent.dig(:next_action, :redirect_to_url, :url)
      end

      def onvo_client
        @client ||= Client.from_env
      end
    end
  end
end
