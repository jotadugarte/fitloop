# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::TestCardNumbers, "[REQ-FIT-BILL-001]" do
  it "recognizes sandbox card numbers with non-digit separators stripped" do
    expect(described_class.include?("4242 4242 4242 4242")).to be(true)
    expect(described_class.include?("9999999999999999")).to be(false)
  end

  it "exposes the primary Visa test PAN" do
    expect(described_class.primary_visa).to eq("4242424242424242")
  end
end
