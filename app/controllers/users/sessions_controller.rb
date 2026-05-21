# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] Sign-out discards ephemeral workspace when confirmed (D19).
  class SessionsController < Devise::SessionsController
    def destroy
      if workspace_logout_requires_confirmation?
        render :confirm_destroy, status: :ok
        return
      end

      Workspace.discard!(session) if workspace_bound?
      super
    end

    private

    def workspace_logout_requires_confirmation?
      workspace_bound? && params[:confirm_workspace_discard].blank?
    end

    def workspace_bound?
      Workspace.find(session).present?
    end
  end
end
