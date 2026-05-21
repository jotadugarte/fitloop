# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nesting enqueue ETA", type: :request do
  include ActiveJob::TestHelper

  let(:project) do
    create_project_for_spec!(
      title: "Enqueue ETA bench",
      status: :draft,
      nesting_time_limit_sec: 600,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end

  before do
    sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)
  end

  describe "POST /projects/:project_id/nesting_runs [REQ-FIT-JOB-001]" do
    it "sets estimated_finished_at from nesting_time_limit_sec, not a 30s stub" do
      before_enqueue = Time.current
      post project_nesting_runs_path(project)
      after_enqueue = Time.current

      project.reload
      expect(project.estimated_finished_at).to be_between(
        before_enqueue + project.nesting_time_limit_sec.seconds - 1.second,
        after_enqueue + project.nesting_time_limit_sec.seconds + 1.second
      )
      expect(project.estimated_finished_at).not_to be_between(
        before_enqueue + 30.seconds,
        after_enqueue + 30.seconds
      )
      expect(project.progress_message).to eq(I18n.t("nesting.phase.queued"))
    end
  end
end
