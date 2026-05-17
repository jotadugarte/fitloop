# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProjectStatusSync do
  let(:project) do
    create_project_for_spec!(title: "Sync bench", pin: "554433").tap do |record|
      record.update!(status: :processing, progress_percent: 3, progress_message: I18n.t("nesting.queued"))
    end
  end

  it "aligns a stuck processing project with a finished nesting run [REQ-FIT-JOB-001]" do
    project.nesting_runs.create!(
      status: "completed",
      started_at: 2.seconds.ago,
      finished_at: Time.current,
      report_json: { "status" => "completed" }
    )

    described_class.call(project: project)

    project.reload
    expect(project).to be_completed
    expect(project.progress_percent).to eq(100)
    expect(project.progress_message).to eq(I18n.t("nesting.completed"))
  end

  it "leaves the project unchanged while the nesting run is still processing" do
    project.nesting_runs.create!(status: "processing", started_at: Time.current)

    described_class.call(project: project)

    project.reload
    expect(project).to be_processing
    expect(project.progress_percent).to eq(3)
  end
end
