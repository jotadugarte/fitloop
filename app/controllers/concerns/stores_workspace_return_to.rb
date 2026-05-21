# frozen_string_literal: true

# [REQ-FIT-AUTH-002] When signing in or up during an ephemeral workspace, return to the bound project (D18).
module StoresWorkspaceReturnTo
  extend ActiveSupport::Concern

  included do
    before_action :store_workspace_return_to!, if: :store_workspace_return_to?
  end

  def after_sign_in_path_for(_resource)
    consume_workspace_return_to || super
  end

  protected

  def consume_workspace_return_to
    session.delete(:workspace_return_to)
  end

  private

  def store_workspace_return_to?
    return false unless devise_controller?
    return false unless request.get?
    return false unless controller_name.in?(%w[sessions registrations])
    return false unless action_name == "new"

    Workspace.bound?(session)
  end

  def store_workspace_return_to!
    project_id = session[Workspace::SESSION_KEY].presence || session.dig(Workspace::WORKSPACES_KEY)&.values&.first
    session[:workspace_return_to] = project_path(project_id)
  end
end
