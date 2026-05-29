# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::RegionalPolicy, "[REQ-FIT-BILL-001]" do
  describe ".for_country [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] forces CRC and 13% IVA for Costa Rica" do
      policy = described_class.for_country("CR")

      expect(policy.fetch(:currency)).to eq(:crc)
      expect(policy.fetch(:iva_applicable)).to be(true)
      expect(policy.fetch(:iva_rate)).to eq(Billing::RegionalPolicy::IVA_RATE)
      expect(policy.fetch(:available_payment_methods)).to eq(%i[sinpe card])
    end

    it "[REQ-FIT-BILL-001] forces USD and no IVA for international clients" do
      policy = described_class.for_country("US")

      expect(policy.fetch(:currency)).to eq(:usd)
      expect(policy.fetch(:iva_applicable)).to be(false)
      expect(policy.fetch(:iva_rate)).to eq(0)
      expect(policy.fetch(:available_payment_methods)).to eq(%i[card])
    end
  end
end
