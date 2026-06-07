# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::HttpTransport do
  let(:config) do
    Billing::Onvo::Config.new(
      secret_key: "onvo_test_secret_key",
      publishable_key: "onvo_test_publishable_key",
      mode: "test",
      webhook_secret: "whsec_test"
    )
  end
  let(:transport) { described_class.new(config: config) }

  describe "#initialize" do
    it "requires config" do
      expect { described_class.new(config: nil) }.to raise_error(ArgumentError, "config required")
    end
  end

  describe "#post" do
    it "makes a POST request to ONVO API" do
      http_double = instance_double(Net::HTTP)
      response_double = instance_double(Net::HTTPResponse, code: "201", body: '{"status": "succeeded"}')

      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:request).and_return(response_double)

      res = transport.post("/payment-intents", { amount: 100 })

      expect(res.status).to eq(201)
      expect(res.body).to eq({ "status" => "succeeded" })
    end
  end

  describe "#get" do
    it "makes a GET request to ONVO API" do
      http_double = instance_double(Net::HTTP)
      response_double = instance_double(Net::HTTPResponse, code: "200", body: '{"id": "pi_123"}')

      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:request).and_return(response_double)

      res = transport.get("/payment-intents/pi_123")

      expect(res.status).to eq(200)
      expect(res.body).to eq({ "id" => "pi_123" })
    end
  end
end
