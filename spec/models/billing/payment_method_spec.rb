# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PaymentMethod, "[REQ-FIT-BILL-001]" do
  describe ".parse" do
    it "accepts card_usd, card_crc, and sinpe_crc" do
      expect(described_class.parse("card_usd").to_s).to eq("card_usd")
      expect(described_class.parse("card_crc").to_s).to eq("card_crc")
      expect(described_class.parse("sinpe_crc").to_s).to eq("sinpe_crc")
    end

    it "rejects unknown methods" do
      expect { described_class.parse("bitcoin") }.to raise_error(ArgumentError)
    end
  end

  describe "predicates" do
    it "identifies card vs sinpe" do
      expect(described_class.parse("card_usd").card?).to be(true)
      expect(described_class.parse("sinpe_crc").sinpe?).to be(true)
      expect(described_class.parse("sinpe_crc").card?).to be(false)
    end
  end

  describe "#billing_method and #currency" do
    it "maps to pricing axis and currency" do
      sinpe = described_class.parse("sinpe_crc")
      expect(sinpe.billing_method.to_sym).to eq(:sinpe)
      expect(sinpe.currency.to_sym).to eq(:crc)

      card = described_class.parse("card_usd")
      expect(card.billing_method.to_sym).to eq(:card)
      expect(card.currency.to_sym).to eq(:usd)
    end
  end
end
