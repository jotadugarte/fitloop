# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::ApiError, "[REQ-FIT-BILL-001]" do
  around do |example|
    I18n.with_locale(:es) { example.run }
  end

  def build_error(body:, message: "ONVO error")
    described_class.new(message, status: 422, body: body)
  end

  it "[REQ-FIT-BILL-001] maps cards.invalid_card_info to Spanish copy" do
    error = build_error(
      body: {
        code: "cards.invalid_card_info",
        message: "There was an error with the card information provided. Please review card number, expiration date and cvv"
      }
    )

    expect(error.user_message).to eq(
      I18n.t("billing.checkout.onvo.api_errors.invalid_card_info")
    )
  end

  it "[REQ-FIT-BILL-001] maps testing payment methods message to Spanish copy" do
    error = build_error(
      body: {
        message: "Only testing payment methods are allowed in test mode"
      }
    )

    expect(error.user_message).to eq(
      I18n.t("billing.checkout.onvo.api_errors.test_payment_method")
    )
  end

  it "[REQ-FIT-BILL-001] maps card information message without code to Spanish copy" do
    error = build_error(
      body: {
        message: "There was an error with the card information provided. Please review card number, expiration date and cvv"
      }
    )

    expect(error.user_message).to eq(
      I18n.t("billing.checkout.onvo.api_errors.invalid_card_info")
    )
  end

  it "[REQ-FIT-BILL-001] falls back to generic Spanish copy for unknown errors" do
    error = build_error(body: { message: "Unexpected processor failure" })

    expect(error.user_message).to eq(
      I18n.t("billing.checkout.onvo.api_errors.generic")
    )
  end
end
