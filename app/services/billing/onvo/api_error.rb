# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] ONVO HTTP API error response.
    class ApiError < StandardError
      attr_reader :status, :body

      def initialize(message, status:, body:)
        super(message)
        @status = status
        @body = body
      end

      def user_message
        detail = extract_detail
        return I18n.t("billing.checkout.onvo.api_errors.test_payment_method") if test_payment_method_error?(detail)

        detail.presence || message
      end

      private

      def extract_detail
        detail = body.is_a?(Hash) ? body[:message] || body["message"] : nil
        detail = detail.join(", ") if detail.is_a?(Array)
        detail
      end

      def test_payment_method_error?(detail)
        detail.to_s.include?("testing payment methods")
      end
    end
  end
end
