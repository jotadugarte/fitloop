# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::TierMonths, "[REQ-FIT-BILL-002]" do
  describe ".parse" do
    it "[REQ-FIT-BILL-002] accepts 1, 2, and 4 months" do
      expect(described_class.parse(1).to_i).to eq(1)
      expect(described_class.parse(2).to_i).to eq(2)
      expect(described_class.parse(4).to_i).to eq(4)
    end

    it "[REQ-FIT-BILL-002] accepts string forms of valid tiers" do
      expect(described_class.parse("1").to_i).to eq(1)
      expect(described_class.parse("2").to_i).to eq(2)
      expect(described_class.parse("4").to_i).to eq(4)
    end

    [ 0, 3, 99, nil ].each do |invalid|
      it "[REQ-FIT-BILL-002] rejects invalid tier_months #{invalid.inspect}" do
        expect { described_class.parse(invalid) }.to raise_error(ArgumentError)
      end
    end
  end

  describe "#to_i" do
    it "[REQ-FIT-BILL-002] returns the canonical integer value" do
      expect(described_class.parse(2).to_i).to eq(2)
    end
  end

  describe ".from_cart" do
    it "[REQ-FIT-BILL-002] builds from a plan cart tier_months column" do
      user = create_billing_user!
      cart = Cart.create!(
        kind: "plan",
        currency_mode: "usd",
        tier_months: 4,
        list_price_cents: 2500,
        sinpe_price_cents: 2000,
        user: user
      )

      expect(described_class.from_cart(cart).to_i).to eq(4)
    end

    it "[REQ-FIT-BILL-002] rejects carts without tier_months" do
      user = create_billing_user!
      run = create_nesting_run!
      cart = Cart.create!(
        kind: "single_download",
        currency_mode: "usd",
        nesting_run: run,
        list_price_cents: 250,
        sinpe_price_cents: 200,
        user: user
      )

      expect { described_class.from_cart(cart) }.to raise_error(ArgumentError)
    end

    it "[REQ-FIT-BILL-002] rejects nil cart" do
      expect { described_class.from_cart(nil) }.to raise_error(ArgumentError, /cart required/)
    end
  end

  describe ".from_record" do
    it "[REQ-FIT-BILL-002] builds from a subscription tier_months column" do
      user = create_billing_user!
      subscription = Subscription.create!(
        user: user,
        tier_months: 2,
        starts_at: Time.current,
        ends_at: 2.months.from_now
      )

      expect(described_class.from_record(subscription).to_i).to eq(2)
    end

    it "[REQ-FIT-BILL-002] rejects nil record" do
      expect { described_class.from_record(nil) }.to raise_error(ArgumentError, /record required/)
    end
  end

  describe "equality and hashing" do
    it "[REQ-FIT-BILL-002] treats equal values as equal" do
      one = described_class.parse(1)
      also_one = described_class.parse("1")

      expect(one).to eq(also_one)
      expect(one.eql?(also_one)).to be(true)
    end

    it "[REQ-FIT-BILL-002] treats different values as unequal" do
      expect(described_class.parse(1)).not_to eq(described_class.parse(2))
    end

    it "[REQ-FIT-BILL-002] implements hash function based on value" do
      one = described_class.parse(1)
      also_one = described_class.parse("1")

      expect(one.hash).to eq(also_one.hash)
    end
  end
end
