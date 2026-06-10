# frozen_string_literal: true

require "rails_helper"

RSpec.describe Feedback::Message, "[REQ-FIT-OPS-001]" do
  it "[REQ-FIT-OPS-001] parses valid messages" do
    message = described_class.parse("  Hola mundo  ")

    expect(message.to_s).to eq("Hola mundo")
    expect(message).to eq(described_class.parse("Hola mundo"))
    expect(message.hash).to eq(described_class.parse("Hola mundo").hash)
  end

  it "[REQ-FIT-OPS-001] rejects blank, short, and long messages" do
    expect { described_class.parse("") }.to raise_error(ArgumentError, /required/)
    expect { described_class.parse("hola") }.to raise_error(ArgumentError, /too short/)
    expect { described_class.parse("a" * 5001) }.to raise_error(ArgumentError, /too long/)
  end
end
