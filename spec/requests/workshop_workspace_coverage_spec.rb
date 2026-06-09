# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workshop workspace edge cases", "[REQ-FIT-UI-005] [REQ-FIT-BILL-001]", type: :request do
  include BillingModelHelpers

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  it "returns unprocessable entity for unknown workspace sections" do
    begin_workspace_session!

    patch workspace_workshop_path, params: { section: "unknown" }

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns unprocessable content when sheet inventory autosave fails validation" do
    project = begin_workspace_session!
    stock = project.sheet_stocks.first!

    allow_any_instance_of(Project).to receive(:save).and_return(false)

    patch workspace_workshop_path,
          params: {
            section: "sheets",
            project: {
              sheet_stocks_attributes: {
                "0" => {
                  id: stock.id,
                  width_mm: stock.width_mm,
                  height_mm: stock.height_mm,
                  quantity: stock.quantity,
                  sort_order: 0
                }
              }
            }
          },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "renders nesting-parameter failures when the project update fails after validation" do
    project = begin_workspace_session!
    project.nesting_runs.create!(status: "failed")

    allow_any_instance_of(Project).to receive(:update).and_return(false)

    patch nesting_parameters_project_path(project),
          params: { project: { kerf_mm: 2, margin_mm: 5 } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "redirects to start when nesting sync loses the bound project" do
    project = begin_workspace_session!
    allow(Nesting::ProjectStatusSync).to receive(:call).and_return(nil)

    get nesting_sync_project_path(project), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to redirect_to(start_project_path)
    expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
  end

  it "returns not found when nested DXF is missing despite authorization" do
    user = create_billing_user!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    sign_in_user! user
    DownloadGrant.create!(
      user: user,
      nesting_run: run,
      kind: "single_purchase",
      retained_until: 1.day.from_now
    )
    grant = DownloadGrant.last
    grant.retained_nested_dxf.attach(
      io: StringIO.new("RETAINED"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )

    get nested_dxf_project_path(project)

    expect(response).to have_http_status(:not_found)
  end
end
