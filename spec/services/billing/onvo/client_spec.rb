# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::Client, "[REQ-FIT-BILL-001]" do
  let(:config) do
    Billing::Onvo::Config.new(
      secret_key: "onvo_test_secret_key",
      publishable_key: "onvo_test_publishable_key",
      mode: "test",
      webhook_secret: "whsec_test"
    )
  end

  let(:transport) { FakeOnvoTransport.new }
  let(:client) { described_class.new(config: config, transport: transport) }

  describe "#mode [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] exposes ONVO_MODE from config" do
      expect(client.mode).to eq("test")
      expect(client).to be_test_mode
    end
  end

  describe "#create_payment_intent [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] POSTs to /payment-intents with secret authorization" do
      transport.stub_post(
        "/payment-intents",
        status: 201,
        body: { "id" => "pi_abc", "status" => "requires_payment_method" }
      )

      result = client.create_payment_intent(
        amount: 113_000,
        currency: "CRC",
        description: "Fitloop #42",
        metadata: { payment_id: "42" }
      )

      expect(transport.calls.last).to eq(
        method: :post,
        path: "/payment-intents",
        body: {
          amount: 113_000,
          currency: "CRC",
          description: "Fitloop #42",
          metadata: { payment_id: "42" }
        }
      )
      expect(result.fetch(:id)).to eq("pi_abc")
      expect(result.fetch(:status)).to eq("requires_payment_method")
    end
  end

  describe "#get_payment_intent [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] GETs payment intent by id" do
      transport.stub_get(
        "/payment-intents/pi_abc",
        status: 200,
        body: { "id" => "pi_abc", "status" => "succeeded" }
      )

      result = client.get_payment_intent("pi_abc")

      expect(transport.calls.last).to eq(method: :get, path: "/payment-intents/pi_abc", body: nil)
      expect(result.fetch(:status)).to eq("succeeded")
    end
  end

  describe "#create_payment_method [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] POSTs to /payment-methods" do
      transport.stub_post(
        "/payment-methods",
        status: 201,
        body: { "id" => "pm_mobile", "type" => "mobile_number" }
      )

      result = client.create_payment_method(
        type: "mobile_number",
        mobile_number: { identification: "1-2345-6789", phone: "88887777" }
      )

      expect(transport.calls.last.fetch(:path)).to eq("/payment-methods")
      expect(result.fetch(:id)).to eq("pm_mobile")
    end
  end

  describe "#confirm_payment_intent [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] POSTs confirm with paymentMethodId" do
      transport.stub_post(
        "/payment-intents/pi_abc/confirm",
        status: 200,
        body: { "id" => "pi_abc", "status" => "processing" }
      )

      result = client.confirm_payment_intent("pi_abc", payment_method_id: "pm_mobile")

      expect(transport.calls.last).to eq(
        method: :post,
        path: "/payment-intents/pi_abc/confirm",
        body: { paymentMethodId: "pm_mobile" }
      )
      expect(result.fetch(:status)).to eq("processing")
    end

    it "[REQ-FIT-BILL-001] includes returnUrl when provided" do
      transport.stub_post(
        "/payment-intents/pi_abc/confirm",
        status: 200,
        body: { "id" => "pi_abc", "status" => "requires_action" }
      )

      client.confirm_payment_intent(
        "pi_abc",
        payment_method_id: "pm_card",
        return_url: "https://example.com/checkout/retorno"
      )

      expect(transport.calls.last.fetch(:body)).to eq(
        paymentMethodId: "pm_card",
        returnUrl: "https://example.com/checkout/retorno"
      )
    end
  end

  describe "API errors [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] raises Onvo::ApiError on non-success HTTP status" do
      transport.stub_post("/payment-intents", status: 400, body: { "message" => "invalid amount" })

      expect do
        client.create_payment_intent(amount: 0, currency: "USD")
      end.to raise_error(Billing::Onvo::ApiError) { |error|
        expect(error.status).to eq(400)
        expect(error.body).to include(message: "invalid amount")
      }
    end
  end

  describe ".from_env [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] builds config from ENV keys" do
      keys = %w[ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_MODE ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      keys.each do |key|
        ENV[key] = case key
        when "ONVO_SECRET_KEY" then "onvo_test_secret_x"
        when "ONVO_PUBLISHABLE_KEY" then "onvo_test_pub_x"
        when "ONVO_MODE" then "test"
        when "ONVO_WEBHOOK_SECRET" then "whsec_x"
        end
      end

      env_client = described_class.from_env(transport: transport)
      expect(env_client.mode).to eq("test")
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end
  end

  class FakeOnvoTransport
    attr_reader :calls

    Response = Struct.new(:status, :body, keyword_init: true)

    def initialize
      @calls = []
      @stubs = {}
    end

    def stub_post(path, status:, body:)
      @stubs[[ "post", path ]] = Response.new(status: status, body: body)
    end

    def stub_get(path, status:, body:)
      @stubs[[ "get", path ]] = Response.new(status: status, body: body)
    end

    def post(path, body)
      @calls << { method: :post, path: path, body: body }
      fetch_stub("post", path)
    end

    def get(path)
      @calls << { method: :get, path: path, body: nil }
      fetch_stub("get", path)
    end

    private

    def fetch_stub(method, path)
      @stubs[[ method, path ]] || raise(KeyError, "no stub for #{method.upcase} #{path}")
    end
  end
end
