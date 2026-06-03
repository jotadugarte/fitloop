# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout geo-based payment methods", "[REQ-FIT-BILL-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def attach_nested_output!(project)
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED DXF CONTENT"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    run
  end

  describe "GET /checkout [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] hides SINPE option when country != CR (D29)" do
      user = create_billing_user!
      project = begin_workspace_session!
      run = attach_nested_output!(project)
      sign_in_user! user

      get checkout_path(nesting_run_id: run.id), headers: { "CF-IPCountry" => "US" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('data-testid="checkout-pay-sinpe-crc"')
    end
  end
end
