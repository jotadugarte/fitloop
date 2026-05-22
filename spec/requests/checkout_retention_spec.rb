# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Checkout nested DXF retention after workspace loss", type: :request do
  include ActiveSupport::Testing::TimeHelpers

  def sign_in_user!(user)
    sign_in user
  end

  def attach_nested_output!(project, content: "NESTED DXF FOR RETENTION")
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new(content),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    run
  end

  describe "POST /checkout/simular then workshop loss [REQ-FIT-BILL-003]" do
    let(:user) { create_billing_user! }

    it "[REQ-FIT-BILL-003] copies nested_dxf to grant on successful checkout (D54)" do
      project = begin_workspace_session!
      run = attach_nested_output!(project)
      sign_in_user! user

      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }

      grant = DownloadGrant.find_by!(user: user, nesting_run: run)
      expect(grant.retained_nested_dxf).to be_attached
      expect(grant.retained_nested_dxf.download).to include("NESTED DXF FOR RETENTION")
      expect(grant.retained_until).to be > Time.current
    end

    it "[REQ-FIT-BILL-003] keeps retained blob after Workspace.discard! (D54)" do
      project = begin_workspace_session!
      run = attach_nested_output!(project)
      sign_in_user! user
      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
      grant = DownloadGrant.find_by!(user: user, nesting_run: run)
      grant_id = grant.id

      Workspace.discard!(session)

      expect(Project.exists?(project.id)).to be(false)
      reloaded = DownloadGrant.find(grant_id)
      expect(reloaded.retained_nested_dxf).to be_attached
      expect(reloaded.retained_nested_dxf.download).to include("NESTED DXF FOR RETENTION")
    end

    it "[REQ-FIT-BILL-003] keeps retained blob after TTL-style expiry and discard (D54)" do
      project = begin_workspace_session!
      run = attach_nested_output!(project)
      sign_in_user! user
      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
      grant_id = DownloadGrant.find_by!(user: user, nesting_run: run).id

      travel_to(5.minutes.from_now) do
        Workspace.discard!(session, tab_id: Workspace::DEFAULT_TAB_ID)
      end

      grant = DownloadGrant.find(grant_id)
      expect(grant.retained_nested_dxf).to be_attached
      expect(grant.retained_nested_dxf.download).to include("NESTED DXF FOR RETENTION")
    end
  end

  describe "Mis pagos download without workshop session bind [REQ-FIT-BILL-003]" do
    let(:user) { create_billing_user! }

    it "[REQ-FIT-BILL-003] downloads from Mis pagos when session has no bound project (D54)" do
      project = begin_workspace_session!
      run = attach_nested_output!(project, content: "MIS PAGOS RETAINED BLOB")
      sign_in_user! user
      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
      grant_id = DownloadGrant.find_by!(user: user, nesting_run: run).id
      Workspace.discard!(session)

      expect(Workspace.bound?(session)).to be(false)

      get mis_pagos_download_path(grant_id)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("MIS PAGOS RETAINED BLOB")
    end

    it "[REQ-FIT-BILL-003] redirects to Mis pagos with auto-download after successful checkout (D54)" do
      project = begin_workspace_session!
      run = attach_nested_output!(project)
      sign_in_user! user

      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }

      grant = DownloadGrant.find_by!(user: user, nesting_run: run)
      expect(response).to redirect_to(mis_pagos_path(auto_download: grant.id))

      follow_redirect!

      expect(response.body).to include('data-testid="mis-pagos-auto-download"')
      expect(response.body).to include(mis_pagos_download_path(grant))
    end

    it "[REQ-FIT-BILL-003] lists downloadable row on Mis pagos after workshop discard (D54)" do
      project = begin_workspace_session!
      run = attach_nested_output!(project)
      sign_in_user! user
      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_usd", outcome: "success" }
      Workspace.discard!(session)

      get mis_pagos_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="mis-pagos-download"')
    end
  end
end
