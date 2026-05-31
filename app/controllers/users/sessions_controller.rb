# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] Sign-out discards ephemeral workspace when confirmed (D19).
  class SessionsController < Devise::SessionsController
    def destroy
      if workspace_logout_requires_confirmation?
        render :confirm_destroy, status: :ok
        return
      end

      Workspace.discard!(session, request: request) if Workspace.active_project?(session)
      super
    end

    private

    def workspace_logout_requires_confirmation?
      return false if params[:confirm_workspace_discard].present?

      Workspace.active_project?(session)
    end
  end
end
