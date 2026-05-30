# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] ONVO API credentials and mode from ENV.
    class Config
      BASE_URL = "https://api.onvopay.com/v1"

      attr_reader :secret_key, :publishable_key, :mode, :webhook_secret

      def self.from_env
        new(
          secret_key: ENV.fetch("ONVO_SECRET_KEY"),
          publishable_key: ENV.fetch("ONVO_PUBLISHABLE_KEY"),
          mode: ENV.fetch("ONVO_MODE", "test"),
          webhook_secret: ENV.fetch("ONVO_WEBHOOK_SECRET")
        )
      end

      def initialize(secret_key:, publishable_key:, mode:, webhook_secret:)
        raise ArgumentError, "secret_key required" if secret_key.to_s.strip.empty?

        @secret_key = secret_key
        @publishable_key = publishable_key
        @mode = mode.to_s
        @webhook_secret = webhook_secret
      end

      def test?
        mode == "test"
      end

      def live?
        mode == "live"
      end
    end
  end
end
