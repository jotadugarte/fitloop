# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::CliRunner do
  let(:project) do
    Project.create!(
      title: "CLI runner bench",
        ephemeral: true,
      sheet_stocks_attributes: {
        "0" => { width_mm: 500, height_mm: 500, quantity: nil, sort_order: 0 }
      }
    )
  end
  let(:nesting_run) { project.nesting_runs.create!(status: "processing", params_snapshot: {}) }

  describe ".call [REQ-FIT-CLI-001]" do
    it "maps non-zero CLI exit to failed status" do
      mock_invoke = ->(_work_dir, _config_path) { 1 }

      described_class.call(nesting_run: nesting_run, invoke: mock_invoke)

      nesting_run.reload
      project.reload

      expect(nesting_run.status).to eq("failed")
      expect(project.status).to eq("failed")
    end
  end
end
