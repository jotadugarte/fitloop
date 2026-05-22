# frozen_string_literal: true

# [REQ-FIT-AUTH-001] Simulate browser tabs via X-Workspace-Tab-Id in rack_test system specs.
module WorkspaceTabSystemHelpers
  TAB_HEADER = "X-Workspace-Tab-Id"

  def set_workspace_tab!(tab_id)
    page.driver.header(TAB_HEADER, tab_id)
  end

  def page_session
    page.driver.request.session
  end

  def bound_project_id_for_tab(tab_id)
    page_session.dig(Workspace::WORKSPACES_KEY, tab_id)
  end

  def start_workspace_in_tab!(tab_id)
    set_workspace_tab!(tab_id)
    visit start_project_path
    bound_project_id_for_tab(tab_id)
  end
end

RSpec.configure do |config|
  config.include WorkspaceTabSystemHelpers, type: :system
end
