# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Money, "[REQ-FIT-BILL-001]" do
  describe ".from_major and .from_cents" do
    it "builds USD money from major units" do
      money = described_class.from_major(2.5, :usd)
      expect(money.amount).to eq(BigDecimal("2.5"))
      expect(money.currency.to_sym).to eq(:usd)
    end

    it "builds from cents" do
      money = described_class.from_cents(250, :usd)
      expect(money.amount).to eq(BigDecimal("2.5"))
    end

    it "rejects negative amounts" do
      expect { described_class.from_major(-1, :usd) }.to raise_error(ArgumentError)
    end
  end

  describe "#+" do
    it "adds same-currency amounts" do
      a = described_class.from_major(1, :usd)
      b = described_class.from_major(2, :usd)
      expect((a + b).amount).to eq(BigDecimal(3))
    end

    it "rejects mixed currency" do
      usd = described_class.from_major(1, :usd)
      crc = described_class.from_major(1, :crc)
      expect { usd + crc }.to raise_error(ArgumentError)
    end
  end

  describe ".from_breakdown_field" do
    it "reads a breakdown hash field" do
      money = described_class.from_breakdown_field({ currency: :usd, list_price: 2.5 }, :list_price)
      expect(money.amount).to eq(BigDecimal("2.5"))
    end
  end
end
