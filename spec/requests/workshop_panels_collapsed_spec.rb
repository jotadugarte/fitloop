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

    doc = Nokogiri::HTML.fragment(body)
    expect(doc.css('details[data-testid="show-sheet-inventory"][open]')).to be_empty
    expect(doc.css('details[data-testid="source-dxf-detail"][open]')).to be_empty
  end

  it "[REQ-FIT-UI-003] opens láminas and DXF panels in setup mode before the first nest" do
    begin_workspace_session!

    get workshop_path

    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to include('data-workshop-setup-mode="true"')

    doc = Nokogiri::HTML.fragment(body)
    expect(doc.css('details[data-testid="show-sheet-inventory"][open]')).not_to be_empty
    expect(doc.css('details[data-testid="source-dxf-detail"][open]')).not_to be_empty
  end

  it "[REQ-FIT-UI-003] keeps panels collapsed even when entering via legacy /projects/:id route (D37)" do
    project = begin_workspace_session!
    enter_taller_mode!(project)

    get "/projects/#{project.id}"

    expect(response).to redirect_to("/taller")
    follow_redirect!

    expect(response).to have_http_status(:ok)
    body = response.body

    doc = Nokogiri::HTML.fragment(body)
    expect(doc.css('details[data-testid="show-sheet-inventory"][open]')).to be_empty
    expect(doc.css('details[data-testid="source-dxf-detail"][open]')).to be_empty
  end

  it "[REQ-FIT-UI-003] opens source DXF detail after uploading on Mi taller so layers stay visible (D37)" do
    sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
    project = begin_workspace_session!
    enter_taller_mode!(project)

    post project_input_dxf_files_path(project),
         params: { files: [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] },
         headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:ok)
    body = response.body
    doc = Nokogiri::HTML.fragment(body)
    expect(doc.css('details[data-testid="source-dxf-detail"]')).not_to be_empty
    expect(doc.css('[data-collapsible-preserve-open]')).not_to be_empty
    expect(doc.css('details[data-testid="source-dxf-detail"][open]')).not_to be_empty
    expect(doc.css('details[data-testid="dxf-file-entry"][open]')).not_to be_empty
  end
end
