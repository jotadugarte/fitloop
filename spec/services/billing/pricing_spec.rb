# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Pricing, "[REQ-FIT-BILL-001]" do
  let(:billing_yml) { Rails.root.join("config/billing.yml") }

  around do |example|
    original = File.read(billing_yml)
    described_class.reset_cache!
    example.run
  ensure
    File.write(billing_yml, original)
    FileUtils.touch(billing_yml)
    described_class.reset_cache!
  end

  describe ".load from config/billing.yml [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] exposes seed prices from billing.yml (D53)" do
      expect(described_class.single_download_usd).to eq(2.0)
      expect(described_class.single_download_sinpe_crc).to eq(1000)
      expect(described_class.single_download_official_crc).to eq(1200)
      expect(described_class.single_download_sinpe_crc).to eq(1000)
      expect(described_class.single_download_official_usd).to eq(2.5)
      expect(described_class.single_download_sinpe_usd).to eq(2.0)
      expect(described_class.single_download_overage_official_crc).to eq(600)
      expect(described_class.single_download_overage_sinpe_crc).to eq(500)
      expect(described_class.single_download_overage_official_usd).to eq(1.25)
      expect(described_class.single_download_overage_sinpe_usd).to eq(1.0)
      expect(described_class.plan_1_month_card_usd).to eq(7.0)
      expect(described_class.plan_1_month_sinpe_usd).to eq(6.5)
      expect(described_class.plan_1_month_official_crc).to eq(3250)
      expect(described_class.plan_1_month_sinpe_crc).to eq(3000)
      expect(described_class.plan_2_months_card_usd).to eq(11.5)
      expect(described_class.plan_2_months_sinpe_usd).to eq(10.75)
      expect(described_class.plan_2_months_official_crc).to eq(5300)
      expect(described_class.plan_2_months_sinpe_crc).to eq(5000)
      expect(described_class.plan_4_months_card_usd).to eq(18.0)
      expect(described_class.plan_4_months_sinpe_usd).to eq(17.0)
      expect(described_class.plan_4_months_official_crc).to eq(8400)
      expect(described_class.plan_4_months_sinpe_crc).to eq(8000)
    end

    it "[REQ-FIT-BILL-001] requires all amounts to be positive" do
      expect(described_class.single_download_usd).to be > 0
      expect(described_class.single_download_sinpe_crc).to be > 0
      expect(described_class.plan_1_month_card_usd).to be > 0
      expect(described_class.plan_4_months_sinpe_crc).to be > 0
    end
  end

  describe "hot-reload on mtime [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] reloads values when billing.yml changes on disk (D53)" do
      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write(File.read(billing_yml))
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))

      described_class.reset_cache!
      expect(described_class.single_download_usd).to eq(2.0)

      sleep 1.1
      temp.write(File.read(billing_yml).gsub("single_download_usd: 2.00", "single_download_usd: 3.50"))
      temp.close
      FileUtils.touch(temp.path, mtime: Time.now + 2)

      expect(described_class.single_download_usd).to eq(3.5)
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end
  end

  describe "plan quota overage pricing [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] charges 50% of single-download price when monthly quota is exhausted (D34)" do
      expect(described_class.single_download_overage_usd).to eq(1.0)
      expect(described_class.single_download_overage_sinpe_crc).to eq(500)
    end
  end

  describe "explicit overage amounts (no percent fallback) [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] requires explicit overage keys and does not derive from plan_quota_overage_percent (D28)" do
      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write(<<~YAML)
        single_download_usd: 2.00
        single_download_sinpe_crc: 1000
        plan_quota_overage_percent: 50
      YAML
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))

      described_class.reset_cache!
      expect { described_class.single_download_overage_usd }.to raise_error(KeyError)
      expect { described_class.single_download_overage_sinpe_crc }.to raise_error(KeyError)
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end
  end

  describe "overage percent deprecation [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] does not expose plan_quota_overage_percent as a public pricing API (D28)" do
      expect(described_class).not_to respond_to(:plan_quota_overage_percent)
    end
  end

  describe "MEIC official vs SINPE pricing tables [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] exposes official (card) and SINPE prices for CRC, including explicit overage amounts (D26, D28)" do
      expect(described_class.single_download_official_crc).to eq(1200)
      expect(described_class.single_download_sinpe_crc).to eq(1000)
      expect(described_class.single_download_overage_official_crc).to eq(600)
      expect(described_class.single_download_overage_sinpe_crc).to eq(500)
    end
  end

  describe "MEIC official vs SINPE pricing tables (USD) [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] exposes official (card) and SINPE prices for USD, including explicit overage amounts (D27, D28)" do
      expect(described_class.single_download_official_usd).to eq(2.50)
      expect(described_class.single_download_sinpe_usd).to eq(2.00)
      expect(described_class.single_download_overage_official_usd).to eq(1.25)
      expect(described_class.single_download_overage_sinpe_usd).to eq(1.00)
    end
  end

  describe ".price API [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] returns official and SINPE amounts per currency and overage flag (D25, D26, D27, D28)" do
      expect(
        described_class.price(product: :single_download, currency: :crc, payment_method: :card, overage: false)
      ).to eq(1200)

      expect(
        described_class.price(product: :single_download, currency: :crc, payment_method: :sinpe, overage: false)
      ).to eq(1000)

      expect(
        described_class.price(product: :single_download, currency: :usd, payment_method: :card, overage: true)
      ).to eq(1.25)

      expect(
        described_class.price(product: :single_download, currency: :usd, payment_method: :card, overage: false)
      ).to eq(2.50)
    end
  end

  describe "nested pricing config format [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] supports nested per-product pricing tables in billing.yml (D25)" do
      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write(<<~YAML)
        products:
          single_download:
            official:
              crc: 1200
              usd: 2.50
            sinpe:
              crc: 1000
              usd: 2.00
            overage:
              official:
                crc: 600
                usd: 1.25
              sinpe:
                crc: 500
                usd: 1.00
      YAML
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))

      described_class.reset_cache!
      expect(described_class.single_download_official_crc).to eq(1200)
      expect(described_class.single_download_overage_official_usd).to eq(1.25)
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end
  end

  describe "config/billing.yml structure [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] uses nested per-product tables as the canonical format (D25)" do
      data = YAML.load_file(billing_yml)
      expect(data).to be_a(Hash)
      expect(data).to have_key("products")
    end
  end

  describe "typed domain arguments [REQ-FIT-BILL-002]" do
    it "accepts TierMonths for plan_price_triple" do
      tier = Billing::TierMonths.parse(2)
      triple = described_class.plan_price_triple(tier)
      expect(triple).to eq([ 11.5, 5300, 5000 ])
    end

    it "accepts BillingMethod and TierMonths for plan price" do
      amount = described_class.price(
        product: :plan,
        currency: Billing::Currency.parse(:crc),
        payment_method: Billing::BillingMethod.parse(:sinpe),
        overage: false,
        tier_months: Billing::TierMonths.parse(1)
      )
      expect(amount).to eq(3000)
    end

    it "rejects invalid tier_months at boundary" do
      expect { described_class.plan_price_triple(3) }.to raise_error(ArgumentError)
    end

    it "rejects sinpe with USD currency" do
      expect do
        described_class.price(
          product: :single_download,
          currency: :usd,
          payment_method: :sinpe,
          overage: false
        )
      end.to raise_error(ArgumentError, /sinpe requires crc/)
    end

    it "prices plan tiers across currency and payment-method resolvers" do
      expect(
        described_class.price(product: :plan, currency: :crc, payment_method: :card, overage: false, tier_months: 1)
      ).to eq(3250)
      expect(
        described_class.price(product: :plan, currency: :crc, payment_method: :sinpe, overage: false, tier_months: 2)
      ).to eq(5000)
      expect(
        described_class.price(product: :plan, currency: :usd, payment_method: :card, overage: false, tier_months: 4)
      ).to eq(18.0)
    end

    it "rejects unsupported products and unknown plan tiers at price resolution" do
      expect do
        described_class.price(product: :bundle, currency: :usd, payment_method: :card, overage: false)
      end.to raise_error(ArgumentError, /unsupported product/)

      expect do
        described_class.price(product: :plan, currency: :usd, payment_method: :card, overage: false, tier_months: 3)
      end.to raise_error(ArgumentError, /invalid tier_months/)
    end

    it "exposes config key presence and non-hash sections safely" do
      expect(described_class.send(:has_key?, "plan_1_month_card_usd")).to be(true)

      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write("misc: plain-string\nsingle_download_usd: 2.00\n")
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))
      described_class.reset_cache!

      expect(described_class.config_section(:misc)).to eq({})
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end
  end

  describe "validate_price_args! and config edge branches [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] rejects non-symbol products and raw boundary types" do
      expect do
        described_class.send(
          :validate_price_args!,
          product: "single_download",
          currency: :crc,
          payment_method: :card,
          overage: false,
          tier_months: nil
        )
      end.to raise_error(ArgumentError, /product must be a Symbol/)

      expect do
        described_class.send(
          :validate_price_args!,
          product: :single_download,
          currency: "crc",
          payment_method: "card",
          overage: false,
          tier_months: nil
        )
      end.not_to raise_error

      expect do
        described_class.send(
          :validate_price_args!,
          product: :single_download,
          currency: :eur,
          payment_method: :card,
          overage: false,
          tier_months: nil
        )
      end.to raise_error(ArgumentError, /invalid currency: eur/)

      expect do
        described_class.send(
          :validate_price_args!,
          product: :single_download,
          currency: :crc,
          payment_method: :paypal,
          overage: false,
          tier_months: nil
        )
      end.to raise_error(ArgumentError, /invalid billing_method: paypal/)

      expect do
        described_class.send(
          :validate_price_args!,
          product: :single_download,
          currency: :crc,
          payment_method: :card,
          overage: nil,
          tier_months: nil
        )
      end.to raise_error(ArgumentError, /overage must be boolean/)
    end

    it "[REQ-FIT-BILL-001] requires tier_months and rejects plan overage" do
      expect do
        described_class.send(
          :validate_price_args!,
          product: :plan,
          currency: :crc,
          payment_method: :card,
          overage: false,
          tier_months: nil
        )
      end.to raise_error(ArgumentError, /tier_months required/)

      expect do
        described_class.send(
          :validate_price_args!,
          product: :plan,
          currency: :crc,
          payment_method: :card,
          overage: true,
          tier_months: 1
        )
      end.to raise_error(ArgumentError, /plan overage is not supported/)
    end

    it "[REQ-FIT-BILL-001] rejects unsupported resolver combinations and non-positive amounts" do
      singleton = described_class.singleton_class
      original = singleton.const_get(:PRICE_KEY_RESOLVERS)
      singleton.send(:remove_const, :PRICE_KEY_RESOLVERS)
      singleton.const_set(:PRICE_KEY_RESOLVERS, {}.freeze)

      expect do
        described_class.price(product: :single_download, currency: :crc, payment_method: :card, overage: false)
      end.to raise_error(ArgumentError, /unsupported currency\/payment_method combination/)
    ensure
      singleton.send(:remove_const, :PRICE_KEY_RESOLVERS)
      singleton.const_set(:PRICE_KEY_RESOLVERS, original)
    end

    it "[REQ-FIT-BILL-001] rejects non-positive price amounts from fetch" do
      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write("single_download_official_crc: 0\n")
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))
      described_class.reset_cache!

      expect do
        described_class.price(product: :single_download, currency: :crc, payment_method: :card, overage: false)
      end.to raise_error(ArgumentError, /must be positive/)
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end

    it "[REQ-FIT-BILL-001] rejects malformed billing.yml structures and missing nested keys" do
      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write("not-a-hash\n")
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))
      described_class.reset_cache!

      expect { described_class.single_download_usd }.to raise_error(ArgumentError, /billing.yml must be a Hash/)
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end

    it "[REQ-FIT-BILL-001] rejects non-hash products section and missing dig paths" do
      expect do
        described_class.send(:normalize_data, { "products" => "invalid" })
      end.to raise_error(ArgumentError, /products must be a Hash/)
    end

    it "[REQ-FIT-BILL-001] raises when nested product pricing paths are incomplete" do
      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write(<<~YAML)
        products:
          single_download:
            official:
              crc: 1200
            sinpe:
              crc: 1000
      YAML
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))
      described_class.reset_cache!

      expect { described_class.single_download_official_usd }.to raise_error(ArgumentError, /billing.yml missing/)
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end

    it "[REQ-FIT-BILL-001] rejects zero values loaded directly through fetch" do
      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write("single_download_usd: 0\n")
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))
      described_class.reset_cache!

      expect { described_class.single_download_usd }.to raise_error(ArgumentError, /single_download_usd must be positive/)
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end

    it "[REQ-FIT-BILL-001] resolves overage and plan tier branches across resolvers" do
      expect(
        described_class.price(product: :single_download, currency: :crc, payment_method: :card, overage: true)
      ).to eq(600)
      expect(
        described_class.price(product: :single_download, currency: :crc, payment_method: :sinpe, overage: true)
      ).to eq(500)
      expect(
        described_class.price(product: :single_download, currency: :usd, payment_method: :card, overage: true)
      ).to eq(1.25)
      expect(
        described_class.price(product: :plan, currency: :crc, payment_method: :card, overage: false, tier_months: 2)
      ).to eq(5300)
      expect(
        described_class.price(product: :plan, currency: :usd, payment_method: :card, overage: false, tier_months: 4)
      ).to eq(18.0)
      expect(described_class.plan_price_triple(1).first).to eq(7.0)
      expect(described_class.plan_price_triple(4).last).to eq(8000)
    end

    it "[REQ-FIT-BILL-001] rejects non-positive CRC amounts during validation" do
      temp = Tempfile.new([ "billing", ".yml" ])
      temp.write("single_download_official_crc: 0\n")
      temp.flush
      stub_const("#{described_class}::CONFIG_PATH", Pathname(temp.path))
      described_class.reset_cache!

      expect do
        described_class.send(:validate_price_amount!, 0, "single_download_official_crc", :crc)
      end.to raise_error(ArgumentError, /amount must be positive/)
    ensure
      temp&.close
      temp&.unlink
      described_class.reset_cache!
    end

    it "[REQ-FIT-BILL-001] raises for unknown plan tiers in helpers" do
      invalid_tier = double(to_i: 3)
      allow(described_class).to receive(:coerce_tier_months).and_return(invalid_tier)

      expect { described_class.plan_price_triple(3) }.to raise_error(ArgumentError, /unknown plan tier_months/)
      expect do
        described_class.send(:plan_key_prefix, invalid_tier)
      end.to raise_error(ArgumentError, /unknown plan tier_months/)
      expect do
        described_class.send(:price_key_for_official_crc, product: :bundle, overage: false, tier_months: nil)
      end.to raise_error(ArgumentError, /unsupported product/)
    end

    it "[REQ-FIT-BILL-001] validates coerced domain objects at the boundary" do
      bad_currency = double("bad currency")
      allow(bad_currency).to receive(:is_a?).with(Billing::Currency).and_return(true)
      allow(bad_currency).to receive(:to_sym).and_return(:eur)
      bad_method = double("bad method")
      allow(bad_method).to receive(:is_a?).with(Billing::BillingMethod).and_return(true)
      allow(bad_method).to receive(:to_sym).and_return(:paypal)
      allow(bad_method).to receive(:compatible_with_currency?).and_return(true)

      expect do
        described_class.send(
          :validate_price_args!,
          product: :single_download,
          currency: bad_currency,
          payment_method: :card,
          overage: false,
          tier_months: nil
        )
      end.to raise_error(ArgumentError, /currency must be :usd or :crc/)

      expect do
        described_class.send(
          :validate_price_args!,
          product: :single_download,
          currency: :crc,
          payment_method: bad_method,
          overage: false,
          tier_months: nil
        )
      end.to raise_error(ArgumentError, /payment_method must be :card or :sinpe/)
    end
  end
end
