# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Plan-included download hint", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  it "[REQ-FIT-BILL-002] shows plan-included message on project when user has active plan quota (D33)" do
    user = create_billing_user!
    project = begin_workspace_session!
    project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    create_active_subscription!(user: user)
    sign_in_user! user

    get project_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="plan-included-download-hint"')
    expect(response.body).to include(I18n.t("billing.download.plan_included"))
  end
end
