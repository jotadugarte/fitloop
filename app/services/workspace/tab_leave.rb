# frozen_string_literal: true

class Workspace
  # Expire ephemeral bind only after the user left the page/tab and returns after TTL (D20).
  module TabLeave
    # Only after a real browser tab/window close (see workspace_tab.js), not Mi cuenta / Mis pagos navigation.
    TAB_LEAVE_TTL = 120.seconds
    TAB_LEFT_COOKIE = "fitloop_workspace_tab_left_at"

    def expire_tab_after_closure!(session, tab_id:, request: nil)
      tid = normalize_tab_id(tab_id)
      project = find(session, tab_id: tid)
      return unless project

      expire_project!(session, project, tab_id: tid, request: request)
    end

    def expire_project_everywhere!(session, project, request: nil)
      cancel_active_nesting!(project)
      Analytics::TrackEvent.call(
        "project_discarded",
        user_id: request&.env&.[]("warden")&.user&.id,
        anonymous_session_key: session[:anonymous_session_key],
        tab_id: DEFAULT_TAB_ID, # since it is everywhere
        project_id: project.id,
        ip: request&.remote_ip,
        user_agent: request&.user_agent,
        country_code: Analytics::ResolveCountry.call(request),
        locale: I18n.locale.to_s,
        properties: project.metadata_snapshot
      )
      project.destroy!
      workspaces_hash(session).delete_if { |_tab, pid| pid.to_i == project.id }
      session[WORKSPACES_KEY] = workspaces_hash(session)
      sync_legacy_session_key!(session)
    end
  end
end
