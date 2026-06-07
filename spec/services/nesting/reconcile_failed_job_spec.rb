# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ReconcileFailedJob, "[REQ-FIT-JOB-001]" do
  let(:project) do
    ProjectSpecFactory.create!(title: "Reconcile failed job bench", status: :processing)
  end
  let(:nesting_run) do
    project.nesting_runs.create!(status: "processing", started_at: 2.minutes.ago)
  end

  def create_failed_nesting_job!(nesting_run_id:, arguments: nil)
    payload = arguments || { "arguments" => [ nesting_run_id ] }.to_json
    job = SolidQueue::Job.create!(
      queue_name: "default",
      class_name: "NestingJob",
      arguments: payload,
      priority: 0
    )
    SolidQueue::FailedExecution.create!(job_id: job.id, error: "boom")
    job
  end

  it "returns false when the nesting run is not processing" do
    nesting_run.update!(status: "completed")

    expect(described_class.call(nesting_run: nesting_run)).to be(false)
  end

  it "fails the run when Solid Queue recorded a failed NestingJob for this run" do
    create_failed_nesting_job!(nesting_run_id: nesting_run.id)

    expect(described_class.call(nesting_run: nesting_run)).to be(true)

    nesting_run.reload
    project.reload
    expect(nesting_run.status).to eq("failed")
    expect(project).to be_failed
    expect(project.progress_message).to eq(I18n.t("nesting.failed"))
  end

  it "ignores failed NestingJob rows that target a different nesting run" do
    nesting_run.update!(started_at: 30.seconds.ago)
    other_run = project.nesting_runs.create!(status: "processing", started_at: 30.seconds.ago)
    create_failed_nesting_job!(nesting_run_id: other_run.id)

    expect(described_class.call(nesting_run: nesting_run)).to be(false)
    expect(nesting_run.reload.status).to eq("processing")
  end

  it "fails the run when processing was abandoned without work_dir output" do
    nesting_run.update!(started_at: 3.minutes.ago)

    expect(described_class.call(nesting_run: nesting_run)).to be(true)

    nesting_run.reload
    expect(nesting_run.status).to eq("failed")
  end

  it "returns false for a recent processing run that still has no work_dir" do
    nesting_run.update!(started_at: 30.seconds.ago)

    expect(described_class.call(nesting_run: nesting_run)).to be(false)
    expect(nesting_run.reload.status).to eq("processing")
  end

  it "returns false when work_dir already contains report.json" do
    nesting_run.update!(started_at: 3.minutes.ago)
    output_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output")
    FileUtils.mkdir_p(output_dir)
    File.write(output_dir.join("report.json"), { status: "processing" }.to_json)

    expect(described_class.call(nesting_run: nesting_run)).to be(false)
    expect(nesting_run.reload.status).to eq("processing")
  ensure
    FileUtils.rm_rf(Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s))
  end

  it "parses nesting_run_id from hash job arguments" do
    service = described_class.new(nesting_run: nesting_run)
    job = instance_double(SolidQueue::Job, arguments: { "arguments" => [ nesting_run.id ] })

    expect(service.send(:nesting_run_id_from_job, job)).to eq(nesting_run.id)
  end

  it "returns nil when job arguments are not valid JSON" do
    service = described_class.new(nesting_run: nesting_run)
    job = instance_double(SolidQueue::Job, arguments: "not-json")

    expect(service.send(:nesting_run_id_from_job, job)).to be_nil
  end

  it "returns false when Solid Queue tables are unavailable" do
    create_failed_nesting_job!(nesting_run_id: nesting_run.id)
    connection = instance_double(ActiveRecord::ConnectionAdapters::PostgreSQLAdapter)
    allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
    allow(connection).to receive(:data_source_exists?).with("solid_queue_jobs").and_return(false)
    allow(connection).to receive(:data_source_exists?).with("solid_queue_failed_executions").and_return(true)

    nesting_run.update!(started_at: 30.seconds.ago)

    expect(described_class.call(nesting_run: nesting_run)).to be(false)
  end
end
