# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CentsAmount, "[REQ-FIT-BILL-001]" do
  describe ".parse" do
    it "stores CRC colones as integer major units" do
      amount = described_class.parse(3250, currency: :crc)
      expect(amount.to_i).to eq(3250)
      expect(amount.to_major).to eq(BigDecimal(3250))
    end

    it "converts USD cents to major units" do
      amount = described_class.parse(250, currency: :usd)
      expect(amount.to_major).to eq(BigDecimal("2.5"))
    end

    it "rejects negative cents" do
      expect { described_class.parse(-1, currency: :usd) }.to raise_error(ArgumentError)
    end

    it "rejects nil cents" do
      expect { described_class.parse(nil, currency: :usd) }.to raise_error(ArgumentError, "cents required")
    end

    it "implements value object equality" do
      a = described_class.parse(100, currency: :usd)
      b = described_class.parse(100, currency: :usd)
      c = described_class.parse(200, currency: :usd)

      expect(a).to eq(b)
      expect(a).not_to eq(c)
      expect(a.hash).to eq(b.hash)
    end
  end
end
