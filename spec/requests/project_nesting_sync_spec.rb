# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project nesting sync", type: :request do
  let(:project) do
    create_project_for_spec!(title: "Nesting sync bench", pin: "667788").tap do |record|
      record.update!(status: :processing, progress_percent: 3, progress_message: I18n.t("nesting.queued"))
    end
  end

  before do
    unlock_project_for_spec!(project, pin: "667788")
    project.nesting_runs.create!(
      status: "completed",
      started_at: 2.seconds.ago,
      finished_at: Time.current,
      report_json: { "status" => "completed" }
    )
  end

  it "GET /projects/:id/nesting_sync returns turbo streams for a finished job [REQ-FIT-JOB-001]" do
    get nesting_sync_project_path(project), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("text/vnd.turbo-stream.html")
    expect(response.body).to include("nesting-result")
    expect(response.body).to include(I18n.t("nesting.completed"))

    project.reload
    expect(project).to be_completed
  end

  it "GET /projects/:id reconciles a finished job on show [REQ-FIT-JOB-001]" do
    get project_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="nesting-result"')
    expect(response.body).to include(I18n.t("nesting.completed"))
    expect(response.body).not_to include(I18n.t("nesting.queued"))
  end
end
