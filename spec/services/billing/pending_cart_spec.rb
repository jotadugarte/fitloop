# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PendingCart, "[REQ-FIT-BILL-001]" do
  describe ".from_session [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] returns nil for blank session payload" do
      expect(described_class.from_session(nil)).to be_nil
      expect(described_class.from_session({})).to be_nil
    end

    it "[REQ-FIT-BILL-001] builds a validated download line" do
      pending = described_class.from_session(
        "kind" => "single_download",
        "nesting_run_id" => 42,
        "currency_mode" => "crc"
      )

      expect(pending.kind).to eq("single_download")
      expect(pending.nesting_run_id).to eq(42)
      expect(pending.currency_mode).to eq("crc")
    end

    it "[REQ-FIT-BILL-001] rejects invalid kind" do
      expect do
        described_class.from_session("kind" => "unknown", "currency_mode" => "crc", "nesting_run_id" => 1)
      end.to raise_error(ArgumentError, /invalid kind/)
    end

    it "[REQ-FIT-BILL-001] rejects plan line without tier_months" do
      expect do
        described_class.from_session("kind" => "plan", "currency_mode" => "crc")
      end.to raise_error(ArgumentError, /tier_months required/)
    end
  end
end
