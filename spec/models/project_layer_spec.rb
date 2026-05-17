# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectLayer, type: :model do
  describe "associations [REQ-FIT-DOM-001]" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end
  end

  describe "layer filter [REQ-FIT-DOM-001]" do
    it "stores layer_name and included flag" do
      layer = described_class.new(layer_name: "PIECES", included: true)

      expect(layer.layer_name).to eq("PIECES")
      expect(layer.included).to be(true)
    end
  end
end
