# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::CardInput, "[REQ-FIT-BILL-001]", type: :service do
  it "[REQ-FIT-BILL-001] normalizes valid card fields" do
    result = described_class.parse!(
      holder_name: "María Rodríguez",
      card_number: "4242 4242 4242 4242",
      card_exp: "12/28",
      cvv: "123"
    )

    expect(result.fetch(:card_number)).to eq("4242424242424242")
    expect(result.fetch(:exp_month)).to eq(12)
    expect(result.fetch(:exp_year)).to eq(2028)
  end

  it "[REQ-FIT-BILL-001] rejects non-test card numbers in ONVO test mode" do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ONVO_MODE", "test").and_return("test")

    expect do
      described_class.parse!(
        holder_name: "Test User",
        card_number: "424242424242424242",
        card_exp: "12/28",
        cvv: "123"
      )
    end.to raise_error(ArgumentError, "card_number_test_only")
  end

  it "[REQ-FIT-BILL-001] rejects holder names with invalid characters" do
    expect do
      described_class.parse!(
        holder_name: "Test User 123",
        card_number: "4242424242424242",
        card_exp: "12/28",
        cvv: "123"
      )
    end.to raise_error(ArgumentError, "holder_name_invalid")
  end

  it "[REQ-FIT-BILL-001] rejects letters in card number" do
    expect do
      described_class.parse!(
        holder_name: "Test User",
        card_number: "4242424242424242abc",
        card_exp: "12/28",
        cvv: "123"
      )
    end.to raise_error(ArgumentError, "card_number_invalid")
  end

  it "[REQ-FIT-BILL-001] rejects non-numeric CVV" do
    expect do
      described_class.parse!(
        holder_name: "Test User",
        card_number: "4242424242424242",
        card_exp: "12/28",
        cvv: "abc"
      )
    end.to raise_error(ArgumentError, "card_cvv_invalid")
  end

  it "[REQ-FIT-BILL-001] rejects holder names longer than the maximum" do
    expect do
      described_class.parse!(
        holder_name: "A" * 101,
        card_number: "4242424242424242",
        card_exp: "12/28",
        cvv: "123"
      )
    end.to raise_error(ArgumentError, "holder_name_invalid")
  end

  it "[REQ-FIT-BILL-001] rejects card numbers that fail Luhn validation" do
    expect do
      described_class.parse!(
        holder_name: "Test User",
        card_number: "4242424242424243",
        card_exp: "12/28",
        cvv: "123"
      )
    end.to raise_error(ArgumentError, "card_number_invalid")
  end

  it "[REQ-FIT-BILL-001] rejects card numbers outside the allowed length range" do
    expect do
      described_class.parse!(
        holder_name: "Test User",
        card_number: "424242",
        card_exp: "12/28",
        cvv: "123"
      )
    end.to raise_error(ArgumentError, "card_number_invalid")
  end

  it "[REQ-FIT-BILL-001] rejects expired cards" do
    expect do
      described_class.parse!(
        holder_name: "Test User",
        card_number: "4242424242424242",
        card_exp: "01/20",
        cvv: "123"
      )
    end.to raise_error(ArgumentError, "card_exp_expired")
  end

  it "[REQ-FIT-BILL-001] applies Luhn digit-doubling reduction above nine" do
    input = described_class.new(
      holder_name: "Test User",
      card_number: "5555555555554444",
      card_exp: "12/28",
      cvv: "123"
    )

    expect(input.send(:luhn_valid?, "5555555555554444")).to be(true)
  end

  it "[REQ-FIT-BILL-001] accepts valid holder names with punctuation" do
    result = described_class.parse!(
      holder_name: "María O'Connor-Lee",
      card_number: "4242424242424242",
      card_exp: "12/28",
      cvv: "123"
    )

    expect(result.fetch(:holder_name)).to eq("María O'Connor-Lee")
  end
end
