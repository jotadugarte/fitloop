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
    redirect_to start_project_path, alert: I18n.t("workspace.expired")
  end

  def expire_workspace_after_tab_closure!
    return false unless tab_return_expired?

    Workspace.expire_tab_after_closure!(session, tab_id: workspace_tab_id)
    redirect_to start_project_path, alert: I18n.t("workspace.tab_closed_expired")
    true
  end

  def tab_return_expired?
    raw = cookies[Workspace::TabLeave::TAB_LEFT_COOKIE]
    return false if raw.blank?

    left_at = Time.zone.at(raw.to_i / 1000.0)
    cookies.delete(Workspace::TabLeave::TAB_LEFT_COOKIE)
    left_at < Workspace::TabLeave::TAB_LEAVE_TTL.ago
  end
end
