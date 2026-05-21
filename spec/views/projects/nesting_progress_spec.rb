# frozen_string_literal: true

require "rails_helper"

RSpec.describe "projects/nesting_progress [REQ-FIT-JOB-001] [REQ-FIT-UI-003]", type: :view do
  include NestingProgressHelper

  let(:project) do
    create_project_for_spec!(
      title: "Progress panel bench",
      status: :processing,
      progress_percent: 42,
      progress_message: "Placing pieces on sheets",
      nesting_time_limit_sec: 600,
      estimated_finished_at: 8.minutes.from_now,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end
  let(:active_run) { project.nesting_runs.create!(status: "processing", params_snapshot: {}) }
  before do
    active_run
    I18n.backend.store_translations(
      :en,
      nesting: { phase: { fill: "Placing pieces on sheets" } }
    )
  end

  def render_progress(**extra_locals)
    render partial: "projects/nesting_progress",
           locals: Nesting::ProgressLocals.for(project).merge(extra_locals)
  end

  it "includes cancel and aria-valuetext while processing [REQ-FIT-JOB-001] [REQ-FIT-UI-003]" do
    render_progress

    expect(rendered).to include('data-testid="nesting-progress"')
    expect(rendered).to include('data-testid="cancel-nesting"')
    expect(rendered).not_to include('data-testid="time-remaining"')
    expect(rendered).to include(I18n.t("nesting.cancel"))
    expect(rendered).to include('aria-valuetext="Placing pieces on sheets, 42%"')
  end

  it "omits cancel when there is no active processing run" do
    active_run.update!(status: "failed", finished_at: Time.current)

    render_progress(active_run: nil)

    expect(rendered).not_to include('data-testid="cancel-nesting"')
  end
end
