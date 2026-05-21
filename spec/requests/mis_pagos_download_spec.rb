# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Mis pagos retained download", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def sign_in_user!(user)
    sign_in user
  end

  def attach_nested_output!(project)
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("RETAINED NESTED DXF"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    run
  end

  def purchase_and_discard!(user:)
    project = begin_workspace_session!
    run = attach_nested_output!(project)
    sign_in_user! user
    post checkout_simulate_path,
         params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
    grant = DownloadGrant.find_by!(user: user, nesting_run: run)
    grant_id = grant.id
    Workspace.discard!(session)
    DownloadGrant.find(grant_id)
  end

  describe "GET /mis-pagos/descargas/:id [REQ-FIT-BILL-003]" do
    let(:user) { create_billing_user! }

    it "[REQ-FIT-BILL-003] serves retained nested DXF without workspace project bind (D54)" do
      grant = purchase_and_discard!(user: user)

      get mis_pagos_download_path(grant)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("RETAINED NESTED DXF")
      expect(response.headers["Content-Disposition"]).to include("attachment")
    end

    it "[REQ-FIT-BILL-003] returns 403 when retention window expired (D54)" do
      grant = purchase_and_discard!(user: user)
      grant.update!(retained_until: 1.hour.ago)

      get mis_pagos_download_path(grant)

      expect(response).to have_http_status(:forbidden)
      expect(response.body).to include(I18n.t("billing.download.retention_expired"))
    end

    it "[REQ-FIT-BILL-003] forbids download for another user's grant" do
      grant = purchase_and_discard!(user: user)
      sign_out user
      other = create_billing_user!(email: "other@example.com")
      sign_in other

      get mis_pagos_download_path(grant)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
