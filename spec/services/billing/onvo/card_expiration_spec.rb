# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::CardExpiration, "[REQ-FIT-BILL-001]", type: :service do
  it "[REQ-FIT-BILL-001] parses MM/YY" do
    result = described_class.parse("12/28")

    expect(result.fetch(:exp_month)).to eq(12)
    expect(result.fetch(:exp_year)).to eq(2028)
  end

  it "[REQ-FIT-BILL-001] parses compact digits" do
    result = described_class.parse("0128")

    expect(result.fetch(:exp_month)).to eq(1)
    expect(result.fetch(:exp_year)).to eq(2028)
  end
end
