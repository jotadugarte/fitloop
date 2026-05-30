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

        if sinpe_transfer_already_confirmed?
          sync_transferor_fields_if_changed!
          return instructions_payload
        end

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

        @payment.update!(
          gateway_status: intent.fetch(:status),
          sinpe_transfer_identification: @identification,
          sinpe_transfer_mobile_number: @mobile_number
        )

        instructions_payload(status: intent.fetch(:status))
      end

      private

      def sinpe_transfer_already_confirmed?
        return false unless @payment.sinpe_crc? && @payment.pending? && !@payment.superseded?
        return false if @payment.sinpe_transfer_identification.blank?

        # ONVO accepts one SINPE confirm per intent. Further «Procesar pago» / «Cambiar datos»
        # only updates transferor reference fields and re-shows instructions.
        true
      end

      def sync_transferor_fields_if_changed!
        return if transferor_fields_unchanged?

        @payment.update!(
          sinpe_transfer_identification: @identification,
          sinpe_transfer_mobile_number: @mobile_number
        )
      end

      def transferor_fields_unchanged?
        normalize_digits(@payment.sinpe_transfer_identification) == normalize_digits(@identification) &&
          normalize_digits(@payment.sinpe_transfer_mobile_number) == normalize_digits(@mobile_number)
      end

      def instructions_payload(status: @payment.gateway_status)
        {
          payment_id: @payment.id,
          status: status,
          destination_number: SinpeDestination.number,
          destination_holder_name: SinpeDestination.holder_name,
          amount: @payment.total_amount,
          currency: @payment.currency,
          transfer_identification: @identification,
          transfer_mobile_number: @mobile_number
        }
      end

      def normalize_digits(value)
        value.to_s.gsub(/\D/, "")
      end

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
