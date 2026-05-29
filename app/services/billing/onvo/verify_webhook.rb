# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Verifies ONVO webhook X-Webhook-Secret header.
    class VerifyWebhook
      def self.call(request:, config: nil)
        new(request: request, config: config).call
      end

      def initialize(request:, config: nil)
        @request = request
        @config = config
      end

      def call
        provided = @request.headers["X-Webhook-Secret"].to_s
        expected = onvo_config.webhook_secret.to_s
        return false if provided.blank? || expected.blank?

        secure_compare(provided, expected)
      end

      private

      def onvo_config
        @config ||= Config.from_env
      end

      def secure_compare(provided, expected)
        ActiveSupport::SecurityUtils.secure_compare(
          ::Digest::SHA256.hexdigest(provided),
          ::Digest::SHA256.hexdigest(expected)
        )
      end
    end
  end
end
