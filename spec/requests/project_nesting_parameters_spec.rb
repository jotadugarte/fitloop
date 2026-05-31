# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project nesting parameters on show", "[REQ-FIT-UI-001]", type: :request do
  def taller_project!(kerf_mm: 3, margin_mm: 6)
    project = begin_workspace_session!
    project.update!(kerf_mm: kerf_mm, margin_mm: margin_mm)
    project.nesting_runs.create!(status: "failed", params_snapshot: {})
    project
  end

  it "renders an inline form to edit kerf and margin in taller mode" do
    taller_project!

    get workshop_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="nesting-parameters"')
    expect(response.body).to include('name="project[kerf_mm]"')
    expect(response.body).to include('value="3.0"')
    expect(response.body).to include('name="project[margin_mm]"')
    expect(response.body).to include('value="6.0"')
  end

  it "renders inline setup nesting settings before the first nest" do
    begin_workspace_session!

    get workshop_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="setup-nesting-settings"')
    expect(response.body).not_to include('data-testid="nesting-parameters"')
  end

  it "updates nesting parameters in place" do
    project = taller_project!(kerf_mm: 1, margin_mm: 5)

    patch nesting_parameters_project_path(project),
          params: { project: { kerf_mm: 4, margin_mm: 7 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(project.reload.kerf_mm).to eq(4)
    expect(project.margin_mm).to eq(7)
  end
end
