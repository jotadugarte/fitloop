# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] Sign-up with name, terms, time zone; 422 on validation errors.
  class RegistrationsController < Devise::RegistrationsController
    before_action :configure_sign_up_params, only: :create

    def create
      build_resource(sign_up_params)
      apply_registration_extras!(resource)

      resource.save
      if resource.persisted?
        handle_successful_sign_up
      else
        handle_failed_sign_up
      end
    end

    private

    def configure_sign_up_params
      devise_parameter_sanitizer.permit(:sign_up, keys: %i[name time_zone terms_accepted])
    end

    def sign_up_params
      super.except(:terms_accepted)
    end

    def apply_registration_extras!(user)
      return unless params.dig(:user, :terms_accepted) == "1"

      user.terms_accepted_at = Time.current
      user.terms_version = TermsVersion.current
    end

    def handle_successful_sign_up
      if resource.active_for_authentication?
        set_flash_message! :notice, :signed_up
        sign_up(resource_name, resource)
        respond_with resource, location: after_sign_up_path_for(resource)
      else
        set_flash_message! :notice, :"signed_up_but_#{resource.inactive_message}"
        expire_data_after_sign_in!
        respond_with resource, location: after_inactive_sign_up_path_for(resource)
      end
    end

    def handle_failed_sign_up
      clean_up_passwords resource
      set_minimum_password_length
      render :new, status: :unprocessable_entity
    end
  end
end
