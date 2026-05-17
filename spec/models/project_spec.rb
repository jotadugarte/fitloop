# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project, type: :model do
  subject(:project) { described_class.new(title: "Atelier bench") }

  describe "defaults [REQ-FIT-DOM-001]" do
    it "sets kerf_mm to 0" do
      expect(project.kerf_mm).to eq(0)
    end

    it "sets margin_mm to 5" do
      expect(project.margin_mm).to eq(5)
    end

    it "sets curve_tolerance_mm to 0.1" do
      expect(project.curve_tolerance_mm).to eq(0.1)
    end

    it "sets sheet_gap_mm to 15" do
      expect(project.sheet_gap_mm).to eq(15)
    end

    it "sets nesting_time_limit_sec to 600" do
      expect(project.nesting_time_limit_sec).to eq(600)
    end

    it "defaults status to draft" do
      expect(project.status).to eq("draft")
    end
  end

  describe "associations [REQ-FIT-DOM-001]" do
    it "has many sheet_stocks, project_layers, and nesting_runs" do
      names = described_class.reflect_on_all_associations.map(&:name)

      expect(names).to include(:sheet_stocks, :project_layers, :nesting_runs)
    end
  end
end
