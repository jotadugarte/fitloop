# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::ExportPaymentsCsv, "[REQ-FIT-ADMIN-001]", type: :service do
  describe ".call" do
    it "emits UTF-8 BOM, Spanish labels, and Excel-safe identifiers" do
      user = create_billing_user!(email: "csv@example.com")
      Payment.create!(
        user: user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
        amount: 1000, subtotal: 1000, total_amount: 1130, tax_amount: 130,
        paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_csv",
        onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download",
        purchase_reference: "222222222222", sinpe_transfer_identification: "109876543210"
      )

      csv = described_class.call(Payment.all)

      expect(csv.start_with?("\uFEFF")).to be(true)
      expect(csv).to include("SINPE Móvil")
      expect(csv).to include("Exitoso")
      expect(csv).to include(%("=""222222222222"""))
      expect(csv).to include(Payment::DEFAULT_CABYS_CODE)
    end
  end
end
