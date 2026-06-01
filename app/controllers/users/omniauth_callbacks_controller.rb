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
      time_zone = omniauth_time_zone

      existing_oauth = User.find_by(provider: auth.provider.to_s, uid: auth.uid.to_s)
      if existing_oauth
        Analytics::TrackEvent.call(
          "user_logged_in",
          user_id: existing_oauth.id,
          anonymous_session_key: session[:anonymous_session_key],
          ip: request.remote_ip,
          user_agent: request.user_agent,
          country_code: Analytics::ResolveCountry.call(request),
          locale: I18n.locale.to_s
        )
        sign_in_and_redirect existing_oauth, event: :authentication
        return
      end

      email_account = User.find_by(email: auth.info.email.to_s.strip.downcase)
      if email_account && Accounts::OauthCollision.merge_required?(email_account, auth)
        Accounts::OauthCollision.stash!(
          session,
          existing_user: email_account,
          auth: auth,
          time_zone: time_zone
        )
        redirect_to fusionar_cuenta_path
        return
      end

      @user = User.from_omniauth(auth, time_zone: time_zone)
      
      Analytics::TrackEvent.call(
        "account_registered",
        user_id: @user.id,
        anonymous_session_key: session[:anonymous_session_key],
        ip: request.remote_ip,
        user_agent: request.user_agent,
        country_code: Analytics::ResolveCountry.call(request),
        locale: I18n.locale.to_s
      )

      Analytics::TrackEvent.call(
        "user_logged_in",
        user_id: @user.id,
        anonymous_session_key: session[:anonymous_session_key],
        ip: request.remote_ip,
        user_agent: request.user_agent,
        country_code: Analytics::ResolveCountry.call(request),
        locale: I18n.locale.to_s
      )

      sign_in_and_redirect @user, event: :authentication
    end

    def omniauth_time_zone
      request.env.dig("omniauth.params", "time_zone").presence ||
        session[:oauth_time_zone].presence ||
        "America/Costa_Rica"
    end
  end
end
