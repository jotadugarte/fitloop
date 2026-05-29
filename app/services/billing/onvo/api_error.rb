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
        detail = body.is_a?(Hash) ? body[:message] || body["message"] : nil
        detail = detail.join(", ") if detail.is_a?(Array)
        detail.presence || message
      end
    end
  end
end
