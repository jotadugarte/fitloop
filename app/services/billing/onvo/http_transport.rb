# frozen_string_literal: true

require "json"
require "net/http"

module Billing
  module Onvo
    # [REQ-FIT-BILL-001] Net::HTTP adapter for ONVO REST API.
    class HttpTransport
      Response = Struct.new(:status, :body, keyword_init: true)

      def initialize(config:)
        raise ArgumentError, "config required" if config.nil?

        @config = config
      end

      def post(path, body)
        request(Net::HTTP::Post, path, body)
      end

      def get(path)
        request(Net::HTTP::Get, path, nil)
      end

      private

      def request(klass, path, body)
        uri = URI("#{Config::BASE_URL}#{path}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true

        request = klass.new(uri)
        request["Authorization"] = "Bearer #{@config.secret_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(body) if body

        response = http.request(request)
        Response.new(status: response.code.to_i, body: parse_body(response.body))
      end

      def parse_body(raw)
        return {} if raw.nil? || raw.strip.empty?

        JSON.parse(raw)
      end
    end
  end
end
