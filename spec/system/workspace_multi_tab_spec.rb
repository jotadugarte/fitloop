# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Workspace multi-tab and tab-close TTL", type: :system do
  include ActiveSupport::Testing::TimeHelpers

  let(:tab_a) { "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa" }
  let(:tab_b) { "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb" }

  it "[REQ-FIT-AUTH-001] gives each tab an independent ephemeral project (D21)" do
    project_a_id = start_workspace_in_tab!(tab_a)
    expect(project_a_id).to be_present

    project_b_id = start_workspace_in_tab!(tab_b)
    expect(project_b_id).to be_present
    expect(project_b_id).not_to eq(project_a_id)

    set_workspace_tab!(tab_a)
    visit project_path(project_a_id)

    expect(page).to have_css('[data-testid="project-show"]')

    set_workspace_tab!(tab_b)
    visit project_path(project_b_id)

    expect(page).to have_css('[data-testid="project-show"]')
  end

  it "[REQ-FIT-AUTH-001] shows tab-closed expired message after 120s away (D20)" do
    project_a_id = start_workspace_in_tab!(tab_a)

    set_workspace_tab!(tab_a)
    page.driver.browser.set_cookie(
      "#{Workspace::TabLeave::TAB_LEFT_COOKIE}=#{(121.seconds.ago.to_f * 1000).to_i}; path=/"
    )
    visit project_path(project_a_id)

    expect(Project.exists?(project_a_id)).to be(false)
    expect(page).to have_css('[data-testid="flash-alert"]')
    expect(page).to have_content(I18n.t("workspace.tab_closed_expired"))
    expect(bound_project_id_for_tab(tab_a)).not_to eq(project_a_id)
  end

  it "[REQ-FIT-AUTH-001] keeps project when returning within 120s after closing the page (D20)" do
    project_a_id = start_workspace_in_tab!(tab_a)
    Project.find(project_a_id).update!(last_activity_at: 10.minutes.ago)

    set_workspace_tab!(tab_a)
    page.driver.browser.set_cookie(
      "#{Workspace::TabLeave::TAB_LEFT_COOKIE}=#{(30.seconds.ago.to_f * 1000).to_i}; path=/"
    )
    visit project_path(project_a_id)

    expect(page).to have_css('[data-testid="project-show"]')
    expect(Project.exists?(project_a_id)).to be(true)
  end
end
