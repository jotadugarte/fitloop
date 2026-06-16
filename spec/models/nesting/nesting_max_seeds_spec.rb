# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::NestingMaxSeeds, "[REQ-FIT-NEST-002]" do
  it "defaults to 16" do
    expect(described_class.from_env.to_i).to eq(16)
  end

  it "rejects non-positive values" do
    expect { described_class.new(0) }.to raise_error(ArgumentError, /positive/)
  end
end
