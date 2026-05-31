# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] Resend confirmation; pre-fill email when already signed in.
  class ConfirmationsController < Devise::ConfirmationsController
    def new
      self.resource = resource_class.new
      resource.email = current_user.email if user_signed_in?
    end

    def show
      super do |resource|
        if resource.errors.empty?
          Analytics::TrackEvent.call(
            "email_confirmed",
            user_id: resource.id,
            anonymous_session_key: session[:anonymous_session_key],
            ip: request.remote_ip,
            user_agent: request.user_agent,
            country_code: Analytics::ResolveCountry.call(request),
            locale: I18n.locale.to_s
          )
        end
      end
    end
  end
end
