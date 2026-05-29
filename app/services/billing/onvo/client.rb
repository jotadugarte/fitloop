# frozen_string_literal: true

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] ONVO REST client (payment intents and payment methods).
    class Client
      def self.from_env(transport: nil)
        config = Config.from_env
        new(config: config, transport: transport || HttpTransport.new(config: config))
      end

      def initialize(config:, transport:)
        raise ArgumentError, "config required" if config.nil?
        raise ArgumentError, "transport required" if transport.nil?

        @config = config
        @transport = transport
      end

      attr_reader :mode

      def mode
        @config.mode
      end

      def test_mode?
        @config.test?
      end

      def create_payment_intent(amount:, currency:, description: nil, metadata: nil)
        payload = { amount: amount, currency: currency }
        payload[:description] = description if description
        payload[:metadata] = metadata if metadata
        post_json("/payment-intents", payload)
      end

      def get_payment_intent(payment_intent_id)
        raise ArgumentError, "payment_intent_id required" if payment_intent_id.to_s.strip.empty?

        get_json("/payment-intents/#{payment_intent_id}")
      end

      def create_payment_method(**payload)
        post_json("/payment-methods", payload)
      end

      def confirm_payment_intent(payment_intent_id, payment_method_id:)
        raise ArgumentError, "payment_intent_id required" if payment_intent_id.to_s.strip.empty?
        raise ArgumentError, "payment_method_id required" if payment_method_id.to_s.strip.empty?

        post_json(
          "/payment-intents/#{payment_intent_id}/confirm",
          { paymentMethodId: payment_method_id }
        )
      end

      private

      def post_json(path, payload)
        response = @transport.post(path, payload)
        parse_response(response)
      end

      def get_json(path)
        response = @transport.get(path)
        parse_response(response)
      end

      def parse_response(response)
        status = response.status
        body = deep_symbolize(response.body)
        return body if status >= 200 && status < 300

        raise ApiError.new(
          "ONVO API error #{status}",
          status: status,
          body: body
        )
      end

      def deep_symbolize(value)
        case value
        when Hash
          value.transform_keys(&:to_sym).transform_values { |v| deep_symbolize(v) }
        when Array
          value.map { |item| deep_symbolize(item) }
        else
          value
        end
      end
    end
  end
end
