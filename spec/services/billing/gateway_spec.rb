# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Gateway, "[REQ-FIT-BILL-001]", type: :service do
  around do |example|
    previous = ENV["BILLING_GATEWAY"]
    example.run
  ensure
    previous.nil? ? ENV.delete("BILLING_GATEWAY") : ENV["BILLING_GATEWAY"] = previous
  end

  it "[REQ-FIT-BILL-001] defaults to simulate when unset" do
    ENV.delete("BILLING_GATEWAY")
    expect(described_class).to be_simulate
    expect(described_class).not_to be_onvo
  end

  it "[REQ-FIT-BILL-001] enables onvo mode from ENV" do
    ENV["BILLING_GATEWAY"] = "onvo"
    expect(described_class).to be_onvo
  end
end
