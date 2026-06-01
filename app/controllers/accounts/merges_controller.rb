# frozen_string_literal: true

module Accounts
  # [REQ-FIT-AUTH-002] Opt-in merge screen when OAuth email collides with an existing account.
  class MergesController < ApplicationController
    def new
      @pending = OauthCollision.pending(session)
      return redirect_to(new_user_session_path, alert: t("auth.merge.expired")) unless @pending

      @existing_user = @pending[:user]
    end

    def create
      pending = OauthCollision.pending(session)
      return redirect_to(new_user_session_path, alert: t("auth.merge.expired")) unless pending

      user = Accounts::Merge.apply!(
        user: pending[:user],
        pending_oauth: pending[:oauth],
        password: merge_params[:password]
      )
      OauthCollision.clear!(session)
      sign_in(:user, user)
      Analytics::TrackEvent.call(
        "user_logged_in",
        user_id: user.id,
        anonymous_session_key: session[:anonymous_session_key],
        ip: request.remote_ip,
        user_agent: request.user_agent,
        country_code: Analytics::ResolveCountry.call(request),
        locale: I18n.locale.to_s
      )
      redirect_to root_path, notice: t("auth.merge.accepted")
    rescue Accounts::MergeRejected
      flash.now[:alert] = t("auth.merge.invalid_password")
      @pending = pending
      @existing_user = pending[:user]
      render :new, status: :unprocessable_entity
    end

    def destroy
      OauthCollision.clear!(session)
      redirect_to new_user_session_path, alert: t("auth.merge.declined")
    end

    private

    def merge_params
      params.expect(merge: [ :password ])
    end
  end
end
