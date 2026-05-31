# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workshop panels default collapsed", "[REQ-FIT-UI-003]", type: :request do
  def enter_taller_mode!(project)
    project.nesting_runs.create!(status: "failed", params_snapshot: {})
  end

  it "[REQ-FIT-UI-003] renders sheet inventory + source DXF detail collapsed on /taller (D37)" do
    project = begin_workspace_session!
    enter_taller_mode!(project)

    get workshop_path

    expect(response).to have_http_status(:ok)
    body = response.body

    expect(body).to include('data-testid="show-sheet-inventory"')
    expect(body).to include('data-testid="source-dxf-detail"')
    expect(body).to include('data-collapsible-key="workshop-sheet-inventory"')
    expect(body).to include('data-collapsible-key="workshop-source-dxf-detail"')

    inventory_idx = body.index('data-testid="show-sheet-inventory"')
    dxf_idx = body.index('data-testid="source-dxf-detail"')
    expect(inventory_idx).to be < dxf_idx

    inventory_start = body.index('data-testid="show-sheet-inventory"')
    inventory_tag = body.slice(inventory_start - 60, 200)
    expect(inventory_tag).not_to include(" open")

    dxf_start = body.index('data-testid="source-dxf-detail"')
    dxf_tag = body.slice(dxf_start - 60, 220)
    expect(dxf_tag).not_to include(" open")
  end

  it "[REQ-FIT-UI-003] opens láminas and DXF panels in setup mode before the first nest" do
    begin_workspace_session!

    get workshop_path

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include('data-workshop-setup-mode="true"')

    inventory_start = body.index('data-testid="show-sheet-inventory"')
    inventory_tag = body.slice(inventory_start - 60, 200)
    expect(inventory_tag).to include(" open")

    dxf_start = body.index('data-testid="source-dxf-detail"')
    dxf_tag = body.slice(dxf_start - 60, 220)
    expect(dxf_tag).to include(" open")
  end

  it "[REQ-FIT-UI-003] keeps panels collapsed even when entering via legacy /projects/:id route (D37)" do
    project = begin_workspace_session!
    enter_taller_mode!(project)

    get "/projects/#{project.id}"

    expect(response).to redirect_to("/taller")
    follow_redirect!

    expect(response).to have_http_status(:ok)
    body = response.body

    inventory_start = body.index('data-testid="show-sheet-inventory"')
    inventory_tag = body.slice(inventory_start - 60, 200)
    expect(inventory_tag).not_to include(" open")

    dxf_start = body.index('data-testid="source-dxf-detail"')
    dxf_tag = body.slice(dxf_start - 60, 220)
    expect(dxf_tag).not_to include(" open")
  end

  it "[REQ-FIT-UI-003] does not auto-expand source DXF detail after uploading on Mi taller (D37)" do
    sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
    project = begin_workspace_session!
    enter_taller_mode!(project)

    post project_input_dxf_files_path(project),
         params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="source-dxf-detail"')
    expect(response.body).not_to include('data-testid="source-dxf-detail" open')
    expect(response.body).not_to include("data-testid=\"source-dxf-detail\"\n           open")
  end
end
