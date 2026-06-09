# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Money, "[REQ-FIT-BILL-001]" do
  describe ".from_major and .from_cents" do
    it "builds USD money from major units" do
      money = described_class.from_major(2.5, :usd)
      expect(money.amount).to eq(BigDecimal("2.5"))
      expect(money.currency.to_sym).to eq(:usd)
    end

    it "reuses Currency value objects without re-parsing in from_major" do
      currency = Billing::Currency.parse(:usd)

      money = described_class.from_major(BigDecimal("2.5"), currency)

      expect(money.currency).to eq(currency)
    end

    it "builds from cents" do
      money = described_class.from_cents(250, :usd)
      expect(money.amount).to eq(BigDecimal("2.5"))
    end

    it "builds CRC money from major colones without cent scaling" do
      money = described_class.from_cents(113_000, :crc)
      expect(money.amount).to eq(BigDecimal("113000"))
    end

    it "rejects nil major amounts" do
      expect { described_class.from_major(nil, :usd) }.to raise_error(ArgumentError, /amount required/)
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

  describe "value semantics" do
    it "formats, compares, and hashes consistently" do
      left = described_class.from_major(2.5, :usd)
      right = described_class.from_major(2.5, :usd)

      expect(left.to_s).to eq("2.50 usd")
      expect(left).to eq(right)
      expect(left.hash).to eq(right.hash)
    end
  end

  describe ".from_breakdown_field" do
    it "reads a breakdown hash field" do
      money = described_class.from_breakdown_field({ currency: :usd, list_price: 2.5 }, :list_price)
      expect(money.amount).to eq(BigDecimal("2.5"))
    end

    it "rejects nil hashes" do
      expect { described_class.from_breakdown_field(nil, :list_price) }
        .to raise_error(ArgumentError, /hash required/)
    end
  end

  describe "#initialize" do
    it "parses string currency codes" do
      money = described_class.new(1, "usd")
      expect(money.currency.to_sym).to eq(:usd)
    end

    it "rejects negative amounts on direct initialization" do
      expect { described_class.new(-5, :usd) }.to raise_error(ArgumentError, /non-negative/)
    end
  end
end
