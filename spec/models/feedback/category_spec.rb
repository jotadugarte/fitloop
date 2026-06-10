# frozen_string_literal: true

require "rails_helper"

RSpec.describe Feedback::Category, "[REQ-FIT-OPS-001]" do
  it "[REQ-FIT-OPS-001] parses allowed categories" do
    category = described_class.parse("bug")

    expect(category.to_s).to eq("bug")
    expect(category).to eq(described_class.parse("bug"))
    expect(category.hash).to eq(described_class.parse("bug").hash)
  end

  it "[REQ-FIT-OPS-001] rejects blank and invalid categories" do
    expect { described_class.parse("") }.to raise_error(ArgumentError, /required/)
    expect { described_class.parse("invalid") }.to raise_error(ArgumentError, /invalid/)
  end
end
