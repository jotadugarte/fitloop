# frozen_string_literal: true

require "rails_helper"

RSpec.describe Feedback::SenderEmail, "[REQ-FIT-OPS-001]" do
  it "[REQ-FIT-OPS-001] parses valid emails" do
    email = described_class.parse(" Person@Example.com ")

    expect(email.to_s).to eq("person@example.com")
    expect(email).to eq(described_class.parse("person@example.com"))
    expect(email.hash).to eq(described_class.parse("person@example.com").hash)
  end

  it "[REQ-FIT-OPS-001] returns nil for blank values" do
    expect(described_class.parse(nil)).to be_nil
    expect(described_class.parse("   ")).to be_nil
  end

  it "[REQ-FIT-OPS-001] rejects invalid emails" do
    expect { described_class.parse("not-an-email") }.to raise_error(ArgumentError, /invalid/)
  end
end
