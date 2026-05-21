# frozen_string_literal: true

class Workspace
  # Expire ephemeral bind only after the user left the page/tab and returns after TTL (D20).
  module TabLeave
    TAB_LEAVE_TTL = 120.seconds
    TAB_LEFT_COOKIE = "fitloop_workspace_tab_left_at"

    def expire_tab_after_closure!(session, tab_id:)
      tid = normalize_tab_id(tab_id)
      project = find(session, tab_id: tid)
      return unless project

      expire_project!(session, project, tab_id: tid)
    end
  end
end
