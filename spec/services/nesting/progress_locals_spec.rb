# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProgressLocals, "[REQ-FIT-JOB-001]" do
  let(:project) do
    create_project_for_spec!(
      title: "Progress locals bench",
      status: :processing,
      progress_percent: 55,
      nesting_time_limit_sec: 600,
      estimated_finished_at: 6.minutes.from_now,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end

  describe ".for" do
    it "returns active_run and eta_overrun for processing projects" do
      active_run = project.nesting_runs.create!(status: "processing", params_snapshot: {})

      locals = described_class.for(project)

      expect(locals).to include(
        project: project,
        active_run: active_run,
        time_limit_notice: false
      )
      expect(locals[:eta_overrun]).to be(false)
    end
  end
end
