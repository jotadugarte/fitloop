# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::JobParameters, "[REQ-FIT-CLI-001]" do
  let(:project) do
    create_project_for_spec!(
      title: "Job params",
      bind_workspace: false,
      kerf_mm: 1.5,
      margin_mm: 5,
      curve_tolerance_mm: 0.2,
      sheet_gap_mm: 20,
      nesting_time_limit_sec: 300
    )
  end

  describe "value semantics" do
    it "compares and hashes by component value objects" do
      left = described_class.from_project(project)
      right = described_class.from_project(project)

      expect(left).to eq(right)
      expect(left.hash).to eq(right.hash)
    end
  end

  describe ".from_project" do
    it "mirrors project nesting numerics" do
      params = described_class.from_project(project)

      expect(params.to_config_hash).to eq(
        kerf_mm: 1.5,
        margin_mm: 5.0,
        curve_tolerance_mm: 0.2,
        sheet_gap_mm: 20.0,
        time_limit_sec: 300
      )
    end
  end

  describe "constructor validation [REQ-FIT-CLI-001]" do
    it "requires typed value objects for every component" do
      valid = described_class.from_project(project)
      components = {
        kerf: valid.kerf,
        margin: valid.margin,
        curve_tolerance: valid.curve_tolerance,
        sheet_gap: valid.sheet_gap,
        time_limit: valid.time_limit
      }

      components.each_key do |key|
        args = components.merge(key => "invalid")

        expect { described_class.new(**args) }.to raise_error(ArgumentError, /#{key} required/)
      end
    end
  end
end
