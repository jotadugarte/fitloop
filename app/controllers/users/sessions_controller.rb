# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] Sign-out discards ephemeral workspace when confirmed (D19).
  class SessionsController < Devise::SessionsController
    def create
      super do |user|
        Analytics::TrackEvent.call(
          "user_logged_in",
          user_id: user.id,
          anonymous_session_key: session[:anonymous_session_key],
          ip: request.remote_ip,
          user_agent: request.user_agent,
          country_code: Analytics::ResolveCountry.call(request),
          locale: I18n.locale.to_s
        )
      end
    end

    def destroy
      if workspace_logout_requires_confirmation?
        render :confirm_destroy, status: :ok
        return
      end

      if user_signed_in?
        Analytics::TrackEvent.call(
          "user_logged_out",
          user_id: current_user.id,
          anonymous_session_key: session[:anonymous_session_key],
          ip: request.remote_ip,
          user_agent: request.user_agent,
          country_code: Analytics::ResolveCountry.call(request),
          locale: I18n.locale.to_s
        )
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
