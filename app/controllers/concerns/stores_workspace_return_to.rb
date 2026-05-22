# frozen_string_literal: true

# [REQ-FIT-AUTH-002] When signing in or up during an ephemeral workspace, return to the bound project (D18).
module StoresWorkspaceReturnTo
  extend ActiveSupport::Concern

  included do
    before_action :store_workspace_return_to!, if: :store_workspace_return_to?
  end

  def after_sign_in_path_for(_resource)
    consume_workspace_return_to || workshop_resume_path || super
  end

  protected

  def consume_workspace_return_to
    session.delete(:workspace_return_to)
  end

  def workshop_resume_path
    project = Workspace.any_bound_project(session, prefer_tab_id: workspace_tab_id)
    return nil unless project

    tid = workspace_tab_id
    Workspace.bind!(session, project, tab_id: tid) if Workspace.tab_id_for_project(session, project.id) != tid
    project_path(project)
  end

  private

  def store_workspace_return_to?
    return false unless devise_controller?
    return false unless request.get?
    return false unless controller_name.in?(%w[sessions registrations])
    return false unless store_workspace_return_to_action?

    Workspace.bound?(session)
  end

  def store_workspace_return_to_action?
    case controller_name
    when "sessions"
      action_name == "new"
    when "registrations"
      action_name.in?(%w[new edit])
    else
      false
    end
  end

  def store_workspace_return_to!
    return if session[:workspace_return_to].present?

    project = Workspace.any_bound_project(session, prefer_tab_id: workspace_tab_id)
    return if project.blank?

    session[:workspace_return_to] = project_path(project)
  end
end
