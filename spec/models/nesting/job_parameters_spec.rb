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
end
