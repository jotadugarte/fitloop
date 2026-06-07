# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::Onvo::SinpeDestination, "[REQ-FIT-BILL-001]" do
  it "[REQ-FIT-BILL-001] reads number and holder name from billing.yml" do
    expect(described_class.number).to eq("+506 70196686")
    expect(described_class.holder_name).to eq("ONVO Pay")
    expect(described_class.to_h).to eq(
      number: "+506 70196686",
      holder_name: "ONVO Pay"
    )
  end
end
