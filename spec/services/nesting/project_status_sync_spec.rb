# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProjectStatusSync do
  let(:project) do
    create_project_for_spec!(title: "Sync bench").tap do |record|
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
    expect(project.progress_message).to eq("nesting.completed")
  end

  it "leaves the project unchanged while the nesting run is still processing" do
    project.nesting_runs.create!(status: "processing", started_at: Time.current)

    described_class.call(project: project)

    project.reload
    expect(project).to be_processing
    expect(project.progress_percent).to eq(3)
  end

  it "does not complete a new run while stale placements_json from a prior nest remain [REQ-FIT-JOB-001] [REQ-FIT-SPLIT-001]" do
    project.placements_json.attach(
      io: StringIO.new('{"placements":[]}'),
      filename: "placements.json",
      content_type: "application/json"
    )
    project.update!(
      status: :partial,
      progress_percent: 100,
      progress_message: I18n.t("nesting.partial")
    )
    project.nesting_runs.create!(status: "processing", started_at: Time.current, params_snapshot: { "nest_updated_pieces" => true })
    project.update!(status: :processing, progress_percent: 3, progress_message: I18n.t("nesting.queued"))

    described_class.call(project: project)

    project.reload
    expect(project).to be_processing
    expect(project.progress_percent).to eq(3)
    expect(project.progress_message).to eq(I18n.t("nesting.queued"))
  end

  it "reconciles an abandoned processing run with no work_dir output [REQ-FIT-JOB-001]" do
    run = project.nesting_runs.create!(status: "processing", started_at: 3.minutes.ago)

    described_class.call(project: project)

    project.reload
    run.reload
    expect(run.status).to eq("failed")
    expect(project).to be_failed
  end

  it "reconciles a cancelled processing run [REQ-FIT-JOB-001]" do
    run = project.nesting_runs.create!(
      status: "processing",
      started_at: Time.current,
      cancel_requested_at: Time.current
    )

    described_class.call(project: project)

    project.reload
    run.reload
    expect(run.status).to eq("failed")
    expect(project).to be_failed
    expect(project.progress_message).to eq("nesting.cancelled")
  end

  it "reconciles a stuck processing run from work_dir report.json [REQ-FIT-JOB-001]" do
    run = project.nesting_runs.create!(status: "processing", started_at: 30.seconds.ago)
    work_dir = Rails.root.join("tmp/nesting_runs", run.id.to_s, "output")
    FileUtils.mkdir_p(work_dir)
    File.write(
      work_dir.join("report.json"),
      { status: "completed", sheets_used: 1 }.to_json
    )

    described_class.call(project: project)

    project.reload
    run.reload
    expect(run.status).to eq("completed")
    expect(project).to be_completed
    expect(project.progress_percent).to eq(100)
  end
end
