# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PurchaseReference, "[REQ-FIT-BILL-001]", type: :service do
  it "[REQ-FIT-BILL-001] generates a 12-digit numeric string" do
    reference = described_class.generate

    expect(reference).to match(/\A\d{12}\z/)
  end

  it "[REQ-FIT-BILL-001] avoids collisions with existing payments" do
    Payment.create!(
      user: create_billing_user!,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      total_amount: 1130,
      purpose: "single_download",
      purchase_reference: "123456789012"
    )

    allow(SecureRandom).to receive(:random_number).and_return(123_456_789_012, 987_654_321_098)

    expect(described_class.generate).to eq("987654321098")
  end
end
