# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workshop pending payment lock", "[REQ-FIT-BILL-001]", type: :request do
  include ActiveSupport::Testing::TimeHelpers
  let(:user) { create_billing_user! }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

    get start_project_path
    follow_redirect!

    @locked_project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
    @locked_project.update!(title: "Workshop lock", status: :completed, kerf_mm: 0, margin_mm: 5)
    @locked_project.sheet_stocks.create!(width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0)
    post project_input_dxf_files_path(@locked_project, context: "setup"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf") ] }
    @locked_project.reload
    ProjectLayer::SetPrimary.call(@locked_project.project_layers.find_by!(layer_name: "PIECES"))
    @locked_project.nested_dxf.attach(
      io: StringIO.new("NESTED"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    @locked_run = @locked_project.nesting_runs.create!(status: "completed")

    Payment.create!(
      user: user,
      nesting_run: @locked_run,
      status: "pending",
      payment_method: "sinpe_crc",
      currency: "crc",
      amount: 1130,
      total_amount: 1130,
      purpose: "single_download",
      gateway_provider: "onvo",
      onvo_payment_intent_id: "pi_workshop_lock",
      onvo_mode: "test",
      gateway_status: "processing"
    )
  end

  let(:project) { @locked_project }
  let(:run) { @locked_run }

  it "[REQ-FIT-BILL-001] shows lock banner on workshop" do
    get workshop_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="pending-payment-lock-banner"')
    expect(response.body).to include(I18n.t("billing.checkout.pending_workshop_lock.message"))
    expect(response.body).to include("context=workshop")
    expect(response.body).to include('data-testid="renest-nesting"')
    expect(response.body).to include("disabled")
    expect(response.body).to include("pending-payment-lock-fieldset")
    expect(response.body).to include('data-testid="source-dxf-detail"')
    expect(response.body).not_to include('data-testid="remove-dxf-file"')
  end

  it "[REQ-FIT-BILL-001] payment status link shows slow-path processing copy" do
    payment = Payment.find_by!(onvo_payment_intent_id: "pi_workshop_lock")

    get checkout_processing_path(payment, context: "workshop")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(I18n.t("billing.checkout.pending_workshop_lock.processing_status_body"))
    expect(response.body).not_to include(I18n.t("billing.checkout.onvo.processing_body"))
    expect(response.body).to include('data-processing-context="workshop"')
  end

  it "[REQ-FIT-BILL-001] blocks starting a new nest" do
    post workshop_nesting_runs_path

    expect(response).to redirect_to(workshop_path)
    expect(flash[:alert]).to eq(I18n.t("billing.checkout.pending_workshop_lock.message"))
    expect(project.nesting_runs.where(status: "processing").count).to eq(0)
  end

  it "[REQ-FIT-BILL-001] disables nested DXF download in preview" do
    get workshop_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="download-nested-dxf-pending"')
    expect(response.body).not_to include('data-testid="download-nested-dxf"')
  end

  it "[REQ-FIT-BILL-001] blocks nested DXF download and paywall while payment pending" do
    get nested_dxf_workshop_path

    expect(response).to redirect_to(workshop_path)
    expect(flash[:alert]).to eq(I18n.t("billing.checkout.pending_workshop_lock.message"))

    get download_paywall_workshop_path

    expect(response).to redirect_to(workshop_path)
    expect(flash[:alert]).to eq(I18n.t("billing.checkout.pending_workshop_lock.message"))
  end

  it "[REQ-FIT-BILL-001] blocks saving sheet inventory" do
    patch workspace_workshop_path,
          params: {
            section: "sheets",
            project: {
              sheet_stocks_attributes: {
                "0" => {
                  id: project.sheet_stocks.first.id,
                  width_mm: 600,
                  height_mm: 500,
                  quantity: 1,
                  sort_order: 0
                }
              }
            }
          },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
    expect(project.sheet_stocks.first.reload.width_mm).to eq(500)
  end

  it "[REQ-FIT-BILL-001] blocks saving layer selection in Detalle DXF" do
    attachment = project.input_dxf_attachments.first!
    cut = project.project_layers.find_by!(
      layer_name: "PIECES",
      active_storage_attachment_id: attachment.id
    )
    gravado = project.project_layers.create!(
      layer_name: "GRABADO",
      active_storage_attachment_id: attachment.id,
      included: false
    )

    patch workspace_workshop_path,
          params: {
            section: "layers",
            project_layers: {
              attachment.id.to_s => {
                primary_layer_id: cut.id.to_s,
                gravado.id.to_s => { auxiliary: "1" }
              }
            }
          },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
    expect(gravado.reload).to have_attributes(layer_role: nil, included: false)
  end

  it "[REQ-FIT-BILL-001] blocks uploading DXF files in workshop" do
    count_before = project.input_dxf_attachments.count

    post project_input_dxf_files_path(project, context: "show"),
         params: { "files[]" => [ fixture_file_upload(sample_dxf, "second.dxf", "application/dxf") ] },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to redirect_to(workshop_path)
    expect(flash[:alert]).to eq(I18n.t("billing.checkout.pending_workshop_lock.message"))
    expect(project.reload.input_dxf_attachments.count).to eq(count_before)
  end

  it "[REQ-FIT-BILL-001] blocks removing DXF files in workshop" do
    attachment = project.input_dxf_attachments.first!

    delete project_input_dxf_file_path(project, attachment, context: "show"),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }

    expect(response).to redirect_to(workshop_path)
    expect(flash[:alert]).to eq(I18n.t("billing.checkout.pending_workshop_lock.message"))
    expect(project.reload.input_dxf_attachments).to include(attachment)
  end

  it "[REQ-FIT-BILL-001] allows workshop mutations after workshop_lock_minutes elapse" do
    payment = Payment.find_by!(onvo_payment_intent_id: "pi_workshop_lock")
    payment.update!(created_at: 20.minutes.ago)

    post workshop_nesting_runs_path

    expect(flash[:alert]).not_to eq(I18n.t("billing.checkout.pending_workshop_lock.message"))
  end

  it "[REQ-FIT-BILL-001] allows workshop mutations after POST liberar" do
    payment = Payment.find_by!(onvo_payment_intent_id: "pi_workshop_lock")

    post checkout_release_pending_lock_path(payment)

    post workshop_nesting_runs_path

    expect(flash[:alert]).not_to eq(I18n.t("billing.checkout.pending_workshop_lock.message"))
  end
end
