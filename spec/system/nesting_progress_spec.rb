# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nesting progress UI", type: :system do
  include ActiveJob::TestHelper

  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  def slow_progress_invoke
    lambda do |work_dir, _config_path|
      output_dir = work_dir.join("output")
      FileUtils.mkdir_p(output_dir)
      [
        %w[extracting 12],
        %w[fill 45],
        %w[optimizing 68],
        %w[writing_outputs 96]
      ].each do |phase_id, percent|
        output_dir.join("progress.json").write(
          {
            version: 1,
            phase_id: phase_id,
            percent: percent,
            pieces_total: 3,
            pieces_placed: 2
          }.to_json
        )
        sleep 0.55
      end
      output_dir.join("nested.dxf").write("FITLOOP MOCK NESTED DXF\n")
      output_dir.join("placements.json").write({ sheets: [] }.to_json)
      output_dir.join("report.json").write(
        { status: "completed", orphans: [], warnings: [] }.to_json
      )
      0
    end
  end

  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  it "[REQ-FIT-JOB-001] starts nesting and shows completed progress on the project page" do
    project = create_project_for_spec!(title: "Turbo progress bench", sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)

    visit project_path(project)
    click_button I18n.t("nesting.start")

    expect(page).to have_css('[data-testid="nesting-result"]')
    expect(page).to have_css('[data-testid="progress-message"]', text: I18n.t("nesting.completed"))
    expect(page).to have_css('[data-testid="nesting-preview-svg"]')
    expect(page).to have_css('[data-testid="preview-sheet"]', minimum: 1)
  end

  it "[REQ-FIT-JOB-001] [REQ-FIT-QA-001] advances percent and phase during processing via nesting_sync" do
    allow(Nesting::CliRunner).to receive(:call).and_wrap_original do |method, **kwargs|
      method.call(**kwargs.merge(invoke: slow_progress_invoke))
    end

    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test

    project = create_project_for_spec!(
      title: "Live progress bench",
      nesting_time_limit_sec: 600,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)

    visit project_path(project)
    click_button I18n.t("nesting.start")

    expect(page).to have_css('[data-testid="nesting-progress"]')
    expect(page).not_to have_css('[data-testid="nesting-result"]')

    job_error = nil
    job_thread = Thread.new do
      ActiveRecord::Base.connection_pool.with_connection do
        perform_enqueued_jobs
      rescue StandardError => error
        job_error = error
      end
    end
    sync_path = nesting_sync_project_path(project)
    advanced_progress = false

    30.times do
      break unless job_thread.alive?

      page.driver.get sync_path, {}, { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" }
      body = page.driver.response.body
      if body.include?("45%") || body.include?(I18n.t("nesting.phase.fill"))
        advanced_progress = true
        break
      end
      sleep 0.2
    end

    job_thread.join(15)
    ActiveJob::Base.queue_adapter = previous_adapter
    raise job_error if job_error

    expect(advanced_progress).to be(true), "expected progress beyond stale 15% pre-CLI tick"

    project.reload
    expect(project.status).to eq("completed")

    page.driver.get sync_path, {}, { "HTTP_ACCEPT" => "text/vnd.turbo-stream.html" }
    visit project_path(project)
    expect(page).to have_css('[data-testid="nesting-result"]')
    expect(page).to have_css('[data-testid="progress-message"]', text: I18n.t("nesting.completed"))
  end
end
