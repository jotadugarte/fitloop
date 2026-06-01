# frozen_string_literal: true

require "rails_helper"
require "stringio"
require "zip"

RSpec.describe Admin::ExportForm150Xlsx, "[REQ-FIT-ADMIN-001]", type: :service do
  describe ".call" do
    it "returns XLSX with Soporte ventas and Formulario 150 sheets" do
      user = create_billing_user!(email: "form150@example.com")
      Payment.create!(
        user: user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
        amount: 1000, subtotal: 1000, total_amount: 1130, tax_amount: 130,
        paid_at: Time.current, created_at: Time.current,
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_crc_f150",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download",
        product_description: "single_download", purchase_reference: "111111111111"
      )
      Payment.create!(
        user: user, status: "succeeded", payment_method: "card_usd", currency: "usd",
        amount: 2.0, subtotal: 2.0, total_amount: 2.0, tax_amount: 0,
        paid_at: Time.current, created_at: Time.current,
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_usd_f150",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download",
        purchase_reference: "222222222222"
      )

      today = Time.current.to_date.to_s
      xlsx_bytes = described_class.call(
        Payment.all,
        period_label: "#{today} — #{today}"
      )
      expect(xlsx_bytes).to be_a(String)

      workbook_xml = nil
      soporte_xml = nil
      formulario_xml = nil

      Zip::File.open_buffer(xlsx_bytes) do |zip|
        workbook_xml = zip.read("xl/workbook.xml")
        soporte_xml = zip.read("xl/worksheets/sheet1.xml")
        formulario_xml = zip.read("xl/worksheets/sheet2.xml")
      end

      [ workbook_xml, soporte_xml, formulario_xml ].each do |xml|
        xml.force_encoding("UTF-8") if xml.respond_to?(:force_encoding)
      end

      expect(xlsx_bytes.bytes.first(2)).to eq([ 0x50, 0x4B ])
      expect(workbook_xml).to include("Soporte ventas")
      expect(workbook_xml).to include("Formulario 150")
      expect(soporte_xml).to include("Ventas a 13%")
      expect(soporte_xml).to include("Exentas crédito pleno")
      expect(soporte_xml).to include("111111111111")
      expect(soporte_xml).to include("222222222222")
      expect(formulario_xml).to include("SUMIFS")
      expect(formulario_xml).to include("<f>SUMIFS")
      expect(formulario_xml).to include("Total ventas a 13%")
      expect(formulario_xml).not_to include("Total ventas generales gravadas")
      expect(formulario_xml).to include("paid_at")
    end

    it "marks non-succeeded payments as No declarable in soporte" do
      user = create_billing_user!(email: "failed-rubro@example.com")
      Payment.create!(
        user: user, status: "failed", payment_method: "card_crc", currency: "crc",
        amount: 100, subtotal: 100, total_amount: 100, tax_amount: 0,
        paid_at: Time.current, created_at: Time.current,
        gateway_provider: "onvo", onvo_payment_intent_id: "pi_failed_rubro",
        onvo_mode: "test", gateway_status: "failed", purpose: "single_download"
      )

      today = Time.current.to_date.to_s
      xlsx_bytes = described_class.call(Payment.where(user: user), period_label: "#{today} — #{today}")

      soporte_xml = nil
      Zip::File.open_buffer(xlsx_bytes) { |zip| soporte_xml = zip.read("xl/worksheets/sheet1.xml") }
      soporte_xml.force_encoding("UTF-8") if soporte_xml.respond_to?(:force_encoding)

      expect(soporte_xml).to include("No declarable")
    end
  end
end
