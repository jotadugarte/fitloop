# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::SinpeInput, "[REQ-FIT-BILL-001]" do
  it "[REQ-FIT-BILL-001] accepts identification with 9 to 12 digits and 8-digit mobile" do
    result = described_class.parse!(identification: "123456789", mobile_number: "88887777")

    expect(result).to eq(identification: "123456789", mobile_number: "88887777")
  end

  it "[REQ-FIT-BILL-001] strips non-digits from identification and mobile" do
    result = described_class.parse!(identification: "1-2345-6789", mobile_number: "8888-7777")

    expect(result).to eq(identification: "123456789", mobile_number: "88887777")
  end

  it "[REQ-FIT-BILL-001] rejects identification shorter than 9 digits" do
    expect do
      described_class.parse!(identification: "12345678", mobile_number: "88887777")
    end.to raise_error(ArgumentError, "sinpe_identification_invalid")
  end

  it "[REQ-FIT-BILL-001] rejects identification longer than 12 digits" do
    expect do
      described_class.parse!(identification: "1234567890123", mobile_number: "88887777")
    end.to raise_error(ArgumentError, "sinpe_identification_invalid")
  end

  it "[REQ-FIT-BILL-001] rejects mobile numbers that are not exactly 8 digits" do
    expect do
      described_class.parse!(identification: "123456789", mobile_number: "8888777")
    end.to raise_error(ArgumentError, "sinpe_mobile_number_invalid")
  end
end
