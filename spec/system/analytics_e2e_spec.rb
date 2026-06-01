# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Analytics E2E Flow", "[REQ-FIT-ANALYTICS-001]", type: :system do
  let(:admin_user) { create_billing_user!(email: "admin-system-e2e@example.com") }

  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  before do
    admin_user.update!(admin: true)
  end

  it "tracks anonymous workspace_started, merges on login, and shows in dashboard" do
    # 1. Visit start project to trigger anonymous workspace_started
    visit start_project_path

    # Verify anonymous event was recorded in the database
    anon_event = UserEvent.where(event_type: "workspace_started").last
    expect(anon_event).to be_present
    expect(anon_event.user_id).to be_nil
    anon_key = anon_event.anonymous_session_key
    expect(anon_key).to be_present

    # 2. Sign in as admin user through the UI to trigger session merge
    visit new_user_session_path
    fill_in "user_email", with: admin_user.email
    fill_in "user_password", with: "securepassword12"
    click_button I18n.t("auth.session.submit")

    # Verify that the event was merged
    expect(anon_event.reload.user_id).to eq(admin_user.id)

    # 3. Visit admin analytics dashboard
    visit "/admin/analytics"

    # Verify we are on the analytics dashboard and can see the counts
    expect(page).to have_content("workspace_started")
  end
end
