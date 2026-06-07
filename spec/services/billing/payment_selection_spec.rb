# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PaymentSelection, "[REQ-FIT-BILL-001]" do
  describe ".resolve [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] forces CRC from country even when session requests USD (D3, D16)" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      session = { billing_currency: "usd", billing_payment_method: "card" }

      user = instance_double(User, time_zone: "America/Costa_Rica")
      selection = described_class.resolve(request: request, session: session, user: user)

      expect(selection.fetch(:currency)).to eq(:crc)
      expect(selection.fetch(:iva_applicable)).to be(true)
      expect(selection.fetch(:payment_method)).to eq(:card)
    end

    it "[REQ-FIT-BILL-001] defaults to GeoPaymentDefaults when no session payment method (D16)" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "CR" })
      session = {}

      selection = described_class.resolve(request: request, session: session, user: nil)

      expect(selection.fetch(:currency)).to eq(:crc)
      expect(selection.fetch(:payment_method)).to eq(:sinpe)
    end

    it "[REQ-FIT-BILL-001] forces USD and no IVA for international clients" do
      request = instance_double(ActionDispatch::Request, headers: { "CF-IPCountry" => "US" })
      session = { billing_currency: "crc", billing_payment_method: "sinpe" }

      selection = described_class.resolve(request: request, session: session, user: nil)

      expect(selection.fetch(:currency)).to eq(:usd)
      expect(selection.fetch(:iva_applicable)).to be(false)
      expect(selection.fetch(:payment_method)).to eq(:card)
    end

    it "[REQ-FIT-BILL-001] uses Costa Rica time_zone when IP geo is missing (D16)" do
      request = instance_double(ActionDispatch::Request, headers: {}, remote_ip: "127.0.0.1")
      allow(request).to receive(:get_header).and_return(nil)
      session = {}
      user = instance_double(User, time_zone: "America/Costa_Rica")

      selection = described_class.resolve(request: request, session: session, user: user)

      expect(selection.fetch(:currency)).to eq(:crc)
      expect(selection.fetch(:iva_applicable)).to be(true)
    end

    it "raises ArgumentError when session does not respond to []" do
      request = instance_double(ActionDispatch::Request)
      expect {
        described_class.resolve(request: request, session: Object.new, user: nil)
      }.to raise_error(ArgumentError, /session must support \[\]/)
    end
  end

  describe ".parse_currency" do
    it "returns :usd for usd string/symbol" do
      expect(described_class.parse_currency("usd")).to eq(:usd)
      expect(described_class.parse_currency(:usd)).to eq(:usd)
    end

    it "returns :crc for crc string/symbol" do
      expect(described_class.parse_currency("crc")).to eq(:crc)
      expect(described_class.parse_currency(:crc)).to eq(:crc)
    end

    it "returns nil for other values" do
      expect(described_class.parse_currency("eur")).to be_nil
      expect(described_class.parse_currency(nil)).to be_nil
    end
  end
end

