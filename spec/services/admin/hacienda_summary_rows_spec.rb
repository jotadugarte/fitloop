# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::HaciendaSummaryRows, "[REQ-FIT-ADMIN-001]", type: :service do
  describe ".row_values and .totals_row" do
    it "aggregates succeeded CRC payments by day and method" do
      user = create_billing_user!(email: "hacienda@example.com")
      Payment.create!(
        user: user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
        amount: 1000, list_price: 1000, subtotal: 1000, tax_amount: 130, total_amount: 1130,
        paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_h1",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )
      Payment.create!(
        user: user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
        amount: 2000, list_price: 2000, subtotal: 2000, tax_amount: 260, total_amount: 2260,
        paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_h2",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
      )

      grouped = described_class.succeeded_groups(Payment.all, currency: "crc")
      keys = described_class.sorted_keys(grouped, direction: "desc")
      date_str, method = keys.first
      row = described_class.row_values(date_str, "crc", method, grouped.fetch(keys.first))

      expect(row[2]).to eq("SINPE Móvil")
      expect(row[3]).to eq(2)
      expect(row[8]).to eq(3390.0)

      totals = described_class.totals_row(keys, grouped, "crc")
      expect(totals[3]).to eq(2)
      expect(totals[8]).to eq(3390.0)
    end
  end
end
