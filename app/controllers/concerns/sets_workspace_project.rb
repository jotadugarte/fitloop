# frozen_string_literal: true

# Resolves the current project and recovers when an ephemeral workspace was discarded.
module SetsWorkspaceProject
  extend ActiveSupport::Concern

  private

  def set_workspace_project
    return if expire_workspace_after_tab_closure!

    param_id = params[:project_id] || params[:id]
    @project = Workspace.resolve!(session, param_id, tab_id: workspace_tab_id)
  rescue ActiveRecord::RecordNotFound
    recover_workspace_project!(param_id) || redirect_to(
      start_project_path,
      alert: I18n.t("workspace.expired")
    )
  end

  def recover_workspace_project!(param_id)
    project = Project.ephemeral.find_by(id: param_id)
    unless project
      clear_stale_workspace_binds_for!(param_id)
      return false
    end

    return false unless Workspace.bound_to_project?(session, project)

    tid = workspace_tab_id
    return false if Workspace.find(session, tab_id: tid)&.id == project.id

    owner_tab = Workspace.tab_id_for_project(session, project.id)
    if owner_tab.present? && owner_tab != tid && Workspace.find(session, tab_id: tid).present?
      return false
    end

    Workspace.bind!(session, project, tab_id: tid)
    @project = project
    true
  end

  def expire_workspace_after_tab_closure!
    return false unless tab_return_expired?

    param_id = params[:project_id] || params[:id]
    project = Project.ephemeral.find_by(id: param_id.to_i) if param_id.present?

    if project && Workspace.bound_to_project?(session, project)
      Workspace.expire_project_everywhere!(session, project)
    else
      Workspace.expire_tab_after_closure!(session, tab_id: workspace_tab_id)
    end

    redirect_to start_project_path, alert: I18n.t("workspace.tab_closed_expired")
    true
  end

  def clear_stale_workspace_binds_for!(project_id)
    pid = project_id.to_i
    hash = session[Workspace::WORKSPACES_KEY]
    return unless hash.is_a?(Hash)

    hash.delete_if { |_tab, bound_id| bound_id.to_i == pid }
    session[Workspace::WORKSPACES_KEY] = hash
    session.delete(Workspace::SESSION_KEY) if session[Workspace::SESSION_KEY].to_i == pid
  end

  def tab_return_expired?
    raw = cookies[Workspace::TabLeave::TAB_LEFT_COOKIE]
    return false if raw.blank?

    left_at = Time.zone.at(raw.to_i / 1000.0)
    cookies.delete(Workspace::TabLeave::TAB_LEFT_COOKIE)
    left_at < Workspace::TabLeave::TAB_LEAVE_TTL.ago
  end
end
