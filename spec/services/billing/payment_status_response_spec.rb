# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PaymentStatusResponse, "[REQ-FIT-BILL-001]", type: :service do
  include Rails.application.routes.url_helpers

  let(:user) { create_billing_user! }

  it "[REQ-FIT-BILL-001] returns pending status without redirect" do
    payment = Payment.create!(
      user: user,
      nesting_run: create_nesting_run!,
      status: "pending",
      payment_method: "card_crc",
      currency: "crc",
      amount: 100,
      purpose: "single_download"
    )

    payload = described_class.for(payment: payment, routes: self)

    expect(payload.fetch(:status)).to eq("pending")
    expect(payload.fetch(:redirect_url)).to be_nil
  end
end
