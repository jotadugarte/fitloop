# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project nesting parameters on show", type: :request do
  it "renders an inline form to edit kerf and margin" do
    project = create_project_for_spec!(
      title: I18n.t("workspace.default_title"),
      kerf_mm: 3,
      margin_mm: 6,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )

    get project_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="nesting-parameters"')
    expect(response.body).to include('name="project[kerf_mm]"')
    expect(response.body).to include('value="3.0"')
    expect(response.body).to include('name="project[margin_mm]"')
    expect(response.body).to include('value="6.0"')
  end

  it "updates nesting parameters in place" do
    project = create_project_for_spec!(
      title: I18n.t("workspace.default_title"),
      kerf_mm: 1,
      margin_mm: 5,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )

    patch nesting_parameters_project_path(project),
          params: { project: { kerf_mm: 4, margin_mm: 7 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(project.reload.kerf_mm).to eq(4)
    expect(project.margin_mm).to eq(7)
  end
end
