# frozen_string_literal: true

# Resolves the current project and recovers when an ephemeral workspace was discarded.
module SetsWorkspaceProject
  extend ActiveSupport::Concern

  private

  def set_workspace_project
    param_id = params[:project_id] || params[:id]
    @project = Workspace.resolve!(session, param_id, tab_id: workspace_tab_id)
  rescue ActiveRecord::RecordNotFound => e
    if e.message.include?("expired")
      redirect_to start_project_path, alert: I18n.t("workspace.activity_expired")
    else
      redirect_to start_project_path, alert: I18n.t("workspace.expired")
    end
  end
end
