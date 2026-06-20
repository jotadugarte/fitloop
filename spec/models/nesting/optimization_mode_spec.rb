# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::OptimizationMode, "[REQ-FIT-NEST-002]" do
  it "defaults to fast" do
    expect(described_class.from_env.to_s).to eq("fast")
  end

  it "accepts thorough" do
    mode = described_class.new("thorough")

    expect(mode.to_s).to eq("thorough")
  end

  it "rejects unknown modes" do
    expect { described_class.new("turbo") }.to raise_error(ArgumentError, /fast or thorough/)
  end
end
