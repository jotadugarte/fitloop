# frozen_string_literal: true

require "rails_helper"

# [REQ-FIT-AUTH-002] [REQ-FIT-BILL-001]
RSpec.describe "Rate Limiting (Rack::Attack)", type: :request do
  before(:each) do
    Rack::Attack.enabled = true
    if Rack::Attack.cache.store.respond_to?(:clear)
      Rack::Attack.cache.store.clear
    end
  end

  after(:each) do
    Rack::Attack.enabled = false
  end

  describe "Authentication rate limiting" do
    it "[REQ-FIT-AUTH-002] limits requests to POST /iniciar-sesion" do
      5.times do
        post "/iniciar-sesion", params: { user: { email: "test@example.com", password: "password" } }
        expect(response.status).not_to eq(429)
      end

      post "/iniciar-sesion", params: { user: { email: "test@example.com", password: "password" } }
      expect(response.status).to eq(429)
      expect(response.body).to include("Retry later")
    end

    it "[REQ-FIT-AUTH-002] limits requests to POST /crear-cuenta" do
      5.times do
        post "/crear-cuenta", params: { user: { email: "test@example.com", password: "password", password_confirmation: "password" } }
        expect(response.status).not_to eq(429)
      end

      post "/crear-cuenta", params: { user: { email: "test@example.com", password: "password", password_confirmation: "password" } }
      expect(response.status).to eq(429)
      expect(response.body).to include("Retry later")
    end
  end

  describe "Payment rate limiting" do
    it "[REQ-FIT-BILL-001] limits requests to POST /checkout/pagar" do
      5.times do
        post "/checkout/pagar", params: {}
        expect(response.status).not_to eq(429)
      end

      post "/checkout/pagar", params: {}
      expect(response.status).to eq(429)
      expect(response.body).to include("Retry later")
    end

    it "[REQ-FIT-BILL-001] limits requests to SINPE payment confirmation" do
      5.times do
        post "/checkout/pagos/payment_123/sinpe", params: {}
        expect(response.status).not_to eq(429)
      end

      post "/checkout/pagos/payment_123/sinpe", params: {}
      expect(response.status).to eq(429)
      expect(response.body).to include("Retry later")
    end

    it "[REQ-FIT-BILL-001] limits requests to Card payment confirmation" do
      5.times do
        post "/checkout/pagos/payment_123/tarjeta", params: {}
        expect(response.status).not_to eq(429)
      end

      post "/checkout/pagos/payment_123/tarjeta", params: {}
      expect(response.status).to eq(429)
      expect(response.body).to include("Retry later")
    end

    it "[REQ-FIT-BILL-001] does NOT limit requests to webhooks/onvo" do
      10.times do
        post "/webhooks/onvo", params: {}
        expect(response.status).not_to eq(429)
      end
    end
  end
end
