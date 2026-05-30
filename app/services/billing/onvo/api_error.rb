# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] ONVO HTTP API error response.
    class ApiError < StandardError
      I18N_KEYS_BY_CODE = {
        "cards.invalid_card_info" => :invalid_card_info
      }.freeze

      attr_reader :status, :body, :context

      def initialize(message, status:, body:, context: nil)
        super(message)
        @status = status
        @body = body
        @context = context
      end

      def user_message
        I18n.t("billing.checkout.onvo.api_errors.#{i18n_key}")
      end

      private

      def i18n_key
        code = error_code
        return I18N_KEYS_BY_CODE[code] if code && I18N_KEYS_BY_CODE.key?(code)
        return :test_payment_method_sinpe if @context == :sinpe && test_payment_method_error?(extract_detail)
        return :test_payment_method if test_payment_method_error?(extract_detail)
        return :invalid_card_info if invalid_card_info_error?(extract_detail)

        :generic
      end

      def error_code
        return nil unless body.is_a?(Hash)

        (body[:code] || body["code"]).to_s.presence
      end

      def extract_detail
        detail = body.is_a?(Hash) ? body[:message] || body["message"] : nil
        detail = detail.join(", ") if detail.is_a?(Array)
        detail
      end

      def test_payment_method_error?(detail)
        detail.to_s.include?("testing payment methods")
      end

      def invalid_card_info_error?(detail)
        detail.to_s.include?("card information provided")
      end
    end
  end
end
