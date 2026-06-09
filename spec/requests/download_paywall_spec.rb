# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Download paywall", "[REQ-FIT-BILL-001] [REQ-FIT-AUTH-002]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def attach_nested_output!(project)
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    run
  end

  it "[REQ-FIT-BILL-001] records nil user_id for guest paywall views" do
    project = begin_workspace_session!
    attach_nested_output!(project)
    sign_out :user if respond_to?(:sign_out)
    allow(Analytics::TrackEvent).to receive(:call)

    get download_paywall_project_path(project)

    expect(Analytics::TrackEvent).to have_received(:call).with(
      "paywall_viewed",
      hash_including(user_id: nil)
    )
  end

  it "[REQ-FIT-BILL-001] omits duplicate sign-in buttons (header only)" do
    project = begin_workspace_session!
    attach_nested_output!(project)

    get download_paywall_project_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('data-testid="paywall-sign-in"')
    expect(response.body).not_to include('data-testid="paywall-sign-up"')
    expect(response.body).to include('id="paywall-aside-title"')
  end

  it "[REQ-FIT-BILL-002] shows plan download CTA instead of checkout when plan quota is available (D33)" do
    user = create_billing_user!
    create_active_subscription!(user: user)
    tab_a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    sign_in_user! user
    project = start_workspace_for_tab!(tab_a)
    attach_nested_output!(project)

    get download_paywall_project_path(project), headers: { "X-Workspace-Tab-Id" => tab_a }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="paywall-plan-download"')
    expect(response.body).to include('data-testid="paywall-plan-quota-hint"')
    expect(response.body).not_to include('data-testid="paywall-checkout"')
  end

  it "[REQ-FIT-BILL-001] paywall links reach checkout and planes without tab header (D42)" do
    user = create_billing_user!
    tab_a = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
    sign_in_user! user
    project = start_workspace_for_tab!(tab_a)
    run = attach_nested_output!(project)

    get download_paywall_project_path(project), headers: { "X-Workspace-Tab-Id" => tab_a }
    expect(response).to have_http_status(:ok)

    get checkout_path(nesting_run_id: run.id), headers: { "X-Workspace-Tab-Id" => tab_a }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="checkout-demo"')

    get planes_path(project_id: project.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('data-testid="planes-checkout"')
  end

  it "[REQ-FIT-AUTH-002] returns guest to paywall after sign-in from header (D18)" do
    project = begin_workspace_session!
    attach_nested_output!(project)

    get download_paywall_project_path(project)
    expect(session[:workspace_return_to]).to eq(download_paywall_project_path(project))

    get new_user_session_path
    expect(session[:workspace_return_to]).to eq(download_paywall_project_path(project))

    user = create_billing_user!(email: "paywall-return@example.com")
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

    expect(response).to redirect_to(download_paywall_project_path(project))
  end

  it "[REQ-FIT-AUTH-001] redirects to start when tab binds exist without a workspace tab header" do
    tab_id = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
    headers = { "X-Workspace-Tab-Id" => tab_id }
    get start_project_path, headers: headers
    follow_redirect!(headers: headers)
    attach_nested_output!(Workspace.find(session, tab_id: tab_id))

    get download_paywall_workshop_path

    expect(response).to redirect_to(start_project_path)
    expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
  end

  it "[REQ-FIT-BILL-001] hides single-download actions when no downloadable nesting run exists (D9)" do
    project = begin_workspace_session!
    project.update!(status: :completed)

    get download_paywall_project_path(project)

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('data-testid="paywall-checkout"')
    expect(response.body).not_to include('data-testid="paywall-plan-download"')
    expect(response.body).to include('data-testid="paywall-inline-plans"')
  end
end
