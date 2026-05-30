# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::WorkshopLockWindow, "[REQ-FIT-BILL-001]", type: :service do
  include ActiveSupport::Testing::TimeHelpers

  it "[REQ-FIT-BILL-001] computes lock expiry from payment created_at and configured minutes" do
    window = described_class.new(minutes: 15)
    payment = instance_double(Payment, created_at: Time.zone.parse("2026-05-30 10:00:00"))

    expect(window.lock_expires_at(payment)).to eq(Time.zone.parse("2026-05-30 10:15:00"))
  end

  it "[REQ-FIT-BILL-001] reads minutes from billing config via from_config" do
    window = described_class.from_config

    expect(window.minutes).to eq(Billing::PendingCheckoutPolicy.workshop_lock_minutes)
  end
end
