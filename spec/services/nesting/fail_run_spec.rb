# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::FailRun do
  let(:project) do
    create_project_for_spec!(title: "Fail run bench", bind_workspace: false)
  end
  let(:nesting_run) { project.nesting_runs.create!(status: "processing", params_snapshot: {}) }

  it "no-ops when the nesting run has no project [REQ-FIT-JOB-001]" do
    run = instance_double(NestingRun, status: "processing", project: nil)

    expect(described_class.call(nesting_run: run)).to be(false)
  end

  it "marks the run and project failed with a missing-file message [REQ-FIT-JOB-001]" do
    described_class.call(
      nesting_run: nesting_run,
      error: ActiveStorage::FileNotFoundError.new("missing blob")
    )

    project.reload
    nesting_run.reload
    expect(nesting_run.status).to eq("failed")
    expect(project).to be_failed
    expect(project.progress_message).to eq("nesting.input_file_missing")
  end
end
