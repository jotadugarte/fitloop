# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::NestingMaxLocalSearchIterations, "[REQ-FIT-NEST-002]" do
  it "defaults to 12" do
    expect(described_class.from_env.to_i).to eq(12)
  end

  it "allows zero iterations" do
    expect(described_class.new(0).to_i).to eq(0)
  end

  it "rejects negative values" do
    expect { described_class.new(-1) }.to raise_error(ArgumentError, /non-negative/)
  end
end
