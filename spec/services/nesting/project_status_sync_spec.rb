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

  it "leaves the project unchanged while the nesting run is still processing [REQ-FIT-JOB-001]" do
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

  it "returns nil if project is not persisted [REQ-FIT-JOB-001]" do
    expect(described_class.call(project: Project.new)).to be_nil
  end

  it "returns nil if reload raises RecordNotFound [REQ-FIT-JOB-001]" do
    allow(project).to receive(:reload).and_raise(ActiveRecord::RecordNotFound)
    expect(described_class.call(project: project)).to be_nil
  end

  it "handles JSON parser error in report file [REQ-FIT-JOB-001]" do
    allow(Nesting::CliRunner).to receive(:finalize_from_work_dir!).and_return(false)
    allow(Nesting::ApplyCancel).to receive(:call).and_return(false)
    allow(Nesting::ReconcileFailedJob).to receive(:call).and_return(false)
    run = project.nesting_runs.create!(status: "processing", started_at: 30.seconds.ago, cancel_requested_at: Time.current)
    work_dir = Rails.root.join("tmp/nesting_runs", run.id.to_s, "output")
    FileUtils.mkdir_p(work_dir)
    File.write(work_dir.join("report.json"), "invalid json")

    described_class.call(project: project)
    project.reload
    expect(project).to be_failed
  end

  it "returns nil for terminal_report if status is not terminal [REQ-FIT-JOB-001]" do
    allow(Nesting::CliRunner).to receive(:finalize_from_work_dir!).and_return(false)
    allow(Nesting::ApplyCancel).to receive(:call).and_return(false)
    allow(Nesting::ReconcileFailedJob).to receive(:call).and_return(false)
    run = project.nesting_runs.create!(status: "processing", started_at: 30.seconds.ago, cancel_requested_at: Time.current)
    work_dir = Rails.root.join("tmp/nesting_runs", run.id.to_s, "output")
    FileUtils.mkdir_p(work_dir)
    File.write(work_dir.join("report.json"), { status: "processing" }.to_json)

    described_class.call(project: project)
    project.reload
    expect(project).to be_failed
  end

  it "sets progress message to nesting.partial for partial run [REQ-FIT-JOB-001]" do
    project.nesting_runs.create!(
      status: "partial",
      started_at: 2.seconds.ago,
      finished_at: Time.current,
      report_json: { "status" => "partial" }
    )
    described_class.call(project: project)
    project.reload
    expect(project.progress_message).to eq("nesting.partial")
  end

  it "reconciles a run with warning cancelled [REQ-FIT-JOB-001]" do
    project.nesting_runs.create!(
      status: "failed",
      started_at: 2.seconds.ago,
      finished_at: Time.current,
      report_json: { "status" => "failed", "warnings" => [ "cancelled" ] }
    )
    described_class.call(project: project)
    project.reload
    expect(project.progress_message).to eq("nesting.cancelled")
  end

  it "reconciles stale processing when terminal report exists without cancel flag [REQ-FIT-JOB-001]" do
    run = project.nesting_runs.create!(status: "processing", started_at: 30.seconds.ago)
    work_dir = Rails.root.join("tmp/nesting_runs", run.id.to_s, "output")
    FileUtils.mkdir_p(work_dir)
    File.write(work_dir.join("report.json"), { status: "partial", warnings: [] }.to_json)
    allow(Nesting::ApplyCancel).to receive(:call).and_return(false)
    allow(Nesting::ReconcileFailedJob).to receive(:call).and_return(false)
    allow(Nesting::CliRunner).to receive(:finalize_from_work_dir!).and_return(false)

    described_class.call(project: project)

    expect(run.reload.status).to eq("partial")
  end

  it "returns nil from terminal_report when report status is non-terminal [REQ-FIT-JOB-001]" do
    sync = described_class.new(project: project)
    run = project.nesting_runs.create!(status: "processing")
    work_dir = Rails.root.join("tmp/nesting_runs", run.id.to_s, "output")
    FileUtils.mkdir_p(work_dir)
    File.write(work_dir.join("report.json"), { status: "processing" }.to_json)

    expect(sync.send(:terminal_report, run)).to be_nil
  ensure
    FileUtils.rm_rf(Rails.root.join("tmp/nesting_runs", run.id.to_s))
  end

  it "returns nil from infer_terminal_status without cancel or terminal report [REQ-FIT-JOB-001]" do
    sync = described_class.new(project: project)
    run = project.nesting_runs.create!(status: "processing")

    expect(sync.send(:infer_terminal_status, run)).to be_nil
  end

  it "skips stale reconciliation when infer_terminal_status is nil [REQ-FIT-JOB-001]" do
    run = project.nesting_runs.create!(status: "processing", started_at: 30.seconds.ago)
    allow(Nesting::ApplyCancel).to receive(:call).and_return(false)
    allow(Nesting::ReconcileFailedJob).to receive(:call).and_return(false)
    allow(Nesting::CliRunner).to receive(:finalize_from_work_dir!).and_return(false)
    sync = described_class.new(project: project)
    allow(sync).to receive(:stale_processing_run?).with(run).and_return(true)
    allow(sync).to receive(:infer_terminal_status).with(run).and_return(nil)

    sync.send(:reconcile_stale_processing_run!, run)

    expect(run.reload.status).to eq("processing")
  end

  it "treats cancelled runs via report_json warnings without cancel_requested_at [REQ-FIT-JOB-001]" do
    run = project.nesting_runs.create!(
      status: "failed",
      started_at: 2.seconds.ago,
      finished_at: Time.current,
      report_json: { "status" => "failed", "warnings" => [ "cancelled" ] }
    )

    described_class.call(project: project)

    expect(project.reload.progress_message).to eq("nesting.cancelled")
    expect(run.reload.report_json).to be_present
  end
end
