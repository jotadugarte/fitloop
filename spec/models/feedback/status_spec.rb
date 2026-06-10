# frozen_string_literal: true

require "rails_helper"

RSpec.describe Feedback::Status, "[REQ-FIT-OPS-001]" do
  it "[REQ-FIT-OPS-001] defaults blank values to pending" do
    expect(described_class.parse(nil).to_s).to eq("pending")
    expect(described_class.parse("reviewed").to_s).to eq("reviewed")
    expect(described_class.parse("reviewed")).to eq(described_class.parse("reviewed"))
    expect(described_class.parse("reviewed").hash).to eq(described_class.parse("reviewed").hash)
  end

  it "[REQ-FIT-OPS-001] rejects invalid statuses" do
    expect { described_class.parse("invalid") }.to raise_error(ArgumentError, /invalid/)
  end
end
