# frozen_string_literal: true

class Workspace
  # Expire ephemeral bind only after the user left the page/tab and returns after TTL (D20).
  module TabLeave
    # Only after a real browser tab/window close (see workspace_tab.js), not Mi cuenta / Mis pagos navigation.
    TAB_LEAVE_TTL = 120.seconds
    TAB_LEFT_COOKIE = "fitloop_workspace_tab_left_at"

    def expire_tab_after_closure!(session, tab_id:)
      tid = normalize_tab_id(tab_id)
      project = find(session, tab_id: tid)
      return unless project

      expire_project!(session, project, tab_id: tid)
    end

    def expire_project_everywhere!(session, project)
      cancel_active_nesting!(project)
      project.destroy!
      workspaces_hash(session).delete_if { |_tab, pid| pid.to_i == project.id }
      session[WORKSPACES_KEY] = workspaces_hash(session)
      sync_legacy_session_key!(session)
    end
  end
end
