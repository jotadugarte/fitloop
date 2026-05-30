# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::CheckoutLockReason, "[REQ-FIT-BILL-001]", type: :service do
  it "[REQ-FIT-BILL-001] accepts known persisted reason strings" do
    expect(described_class.valid?(described_class::TIMEOUT)).to be(true)
    expect(described_class.valid?(described_class::USER_ABANDONED)).to be(true)
    expect(described_class.valid?(described_class::SUPERSEDED)).to be(true)
    expect(described_class.valid?(described_class::USER_CANCELED_3DS)).to be(true)
  end

  it "[REQ-FIT-BILL-001] rejects unknown reason strings" do
    expect(described_class.valid?("unknown")).to be(false)
  end
end
