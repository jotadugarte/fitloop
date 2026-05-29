# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::CardExpiration, "[REQ-FIT-BILL-001]", type: :service do
  it "[REQ-FIT-BILL-001] parses MM/YY" do
    result = described_class.parse("12/28")

    expect(result.fetch(:exp_month)).to eq(12)
    expect(result.fetch(:exp_year)).to eq(2028)
  end

  it "[REQ-FIT-BILL-001] normalizes four digits into MM/YY" do
    expect(described_class.normalize("1228")).to eq("12/28")
  end

  it "[REQ-FIT-BILL-001] rejects values that cannot form MM/YY" do
    expect { described_class.parse("129") }.to raise_error(ArgumentError, "card_exp_invalid")
  end
end
