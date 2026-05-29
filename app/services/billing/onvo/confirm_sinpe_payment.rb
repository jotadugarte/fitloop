# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Create mobile_number payment method and confirm SINPE intent.
    class ConfirmSinpePayment
      def self.call(payment:, identification:, mobile_number:, client: nil)
        new(payment: payment, identification: identification, mobile_number: mobile_number, client: client).call
      end

      def initialize(payment:, identification:, mobile_number:, client: nil)
        @payment = payment
        @identification = identification.to_s.strip
        @mobile_number = mobile_number.to_s.strip
        @client = client
      end

      def call
        raise ArgumentError, "payment required" if @payment.nil?
        raise ArgumentError, "identification required" if @identification.empty?
        raise ArgumentError, "mobile_number required" if @mobile_number.empty?
        raise ArgumentError, "ONVO intent required" if @payment.onvo_payment_intent_id.blank?

        method = onvo_client.create_payment_method(
          type: "mobile_number",
          mobileNumber: {
            identification: @identification,
            identificationType: 0,
            number: normalize_mobile_number(@mobile_number)
          },
          billing: {
            name: @payment.purchaser_name.presence || @payment.user.name,
            email: @payment.purchaser_email.presence || @payment.user.email
          }
        )

        intent = onvo_client.confirm_payment_intent(
          @payment.onvo_payment_intent_id,
          payment_method_id: method.fetch(:id)
        )

        @payment.update!(gateway_status: intent.fetch(:status))

        {
          payment_id: @payment.id,
          status: intent.fetch(:status),
          destination_number: SinpeDestination.number,
          destination_holder_name: SinpeDestination.holder_name,
          amount: @payment.total_amount,
          currency: @payment.currency
        }
      end

      private

      def onvo_client
        @client ||= Client.from_env
      end

      def normalize_mobile_number(number)
        return number if number.start_with?("+")

        digits = number.gsub(/\D/, "")
        digits = "506#{digits}" if digits.length == 8
        "+#{digits}"
      end
    end
  end
end
