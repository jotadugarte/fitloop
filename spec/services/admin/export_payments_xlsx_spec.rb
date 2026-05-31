# frozen_string_literal: true

require "rails_helper"
require "zip"

RSpec.describe Admin::ExportPaymentsXlsx, "[REQ-FIT-ADMIN-001]", type: :service do
  describe ".call" do
    it "creates separate CRC and USD detail and Hacienda summary sheets" do
      user = create_billing_user!(email: "xlsx-admin@example.com")
      Payment.create!(
        user: user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
        amount: 1000, subtotal: 1000, total_amount: 1130, tax_amount: 130,
        paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_crc",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download",
        product_description: "single_download"
      )
      Payment.create!(
        user: user, status: "succeeded", payment_method: "card_usd", currency: "usd",
        amount: 2.0, subtotal: 2.0, total_amount: 2.0, tax_amount: 0,
        paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_usd",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download",
        purchase_reference: "424561803429"
      )

      xlsx_bytes = described_class.call(Payment.all)
      workbook_xml = nil

      Zip::File.open_buffer(xlsx_bytes) do |zip|
        workbook_xml = zip.read("xl/workbook.xml")
      end

      expect(described_class::DETAIL_HEADERS).to include("Concepto")
      expect(xlsx_bytes.bytes.first(2)).to eq([ 0x50, 0x4B ])
      expect(workbook_xml).to include("Detalle CRC")
      expect(workbook_xml).to include("Detalle USD Export")
      expect(workbook_xml).to include("Resumen Hacienda CRC")
      expect(workbook_xml).to include("Resumen Hacienda USD")
    end
  end
end
