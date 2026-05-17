# frozen_string_literal: true

# Resolves the current project and recovers when an ephemeral workspace was discarded.
module SetsWorkspaceProject
  extend ActiveSupport::Concern

  private

  def set_workspace_project
    param_id = params[:project_id] || params[:id]
    @project = Workspace.resolve!(session, param_id)
  rescue ActiveRecord::RecordNotFound
    Workspace.discard!(session)
    redirect_to start_project_path, alert: I18n.t("workspace.expired")
  end
end
