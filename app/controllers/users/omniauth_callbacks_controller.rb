# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] OAuth sign-in and registration (Google, Facebook, Apple).
  class OmniauthCallbacksController < Devise::OmniauthCallbacksController
    def google_oauth2
      handle_oauth(:google_oauth2)
    end

    def facebook
      handle_oauth(:facebook)
    end

    def apple
      handle_oauth(:apple)
    end

    def failure
      redirect_to new_user_session_path, alert: t("auth.oauth.failure")
    end

    private

    def handle_oauth(_provider)
      auth = request.env["omniauth.auth"]
      @user = User.from_omniauth(auth, time_zone: omniauth_time_zone)
      sign_in_and_redirect @user, event: :authentication
    end

    def omniauth_time_zone
      request.env.dig("omniauth.params", "time_zone").presence ||
        session[:oauth_time_zone].presence ||
        "America/Costa_Rica"
    end
  end
end
