# frozen_string_literal: true

# [REQ-FIT-AUTH-001] Tab id from Stimulus workspace_tab_controller (D21).
module ResolvesWorkspaceTab
  extend ActiveSupport::Concern

  TAB_HEADER = "X-Workspace-Tab-Id"
  TAB_COOKIE = "fitloop_workspace_tab_id"

  private

  def workspace_tab_id
    request.headers[TAB_HEADER].presence ||
      cookies[TAB_COOKIE].presence ||
      Workspace::DEFAULT_TAB_ID
  end
end
