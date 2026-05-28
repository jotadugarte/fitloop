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
      expect(described_class.plan_quota_overage_percent).to eq(50)
      expect(described_class.plan_1_month_card_usd).to eq(6.0)
      expect(described_class.plan_1_month_sinpe_crc).to eq(3000)
      expect(described_class.plan_2_months_card_usd).to eq(10.0)
      expect(described_class.plan_2_months_sinpe_crc).to eq(5000)
      expect(described_class.plan_4_months_card_usd).to eq(16.0)
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

  describe "MEIC official vs SINPE pricing tables [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] exposes official (card) and SINPE prices for CRC, including explicit overage amounts (D26, D28)" do
      expect(described_class.single_download_official_crc).to eq(1200)
      expect(described_class.single_download_sinpe_crc).to eq(1000)
      expect(described_class.single_download_overage_official_crc).to eq(600)
      expect(described_class.single_download_overage_sinpe_crc).to eq(500)
    end
  end
end
