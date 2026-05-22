# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] Sign-up with name, terms, time zone; 422 on validation errors.
  class RegistrationsController < Devise::RegistrationsController
    before_action :configure_sign_up_params, only: :create
    before_action :configure_account_update_params, only: :update

    def update
      self.resource = resource_class.to_adapter.get!(send(:"current_#{resource_name}").to_key)
      prev_unconfirmed_email = resource.unconfirmed_email if resource.respond_to?(:unconfirmed_email)

      if update_resource(resource, account_update_params)
        set_flash_message_for_update(resource, prev_unconfirmed_email)
        bypass_sign_in resource, scope: resource_name if sign_in_after_change_password?
        respond_with resource, location: after_update_path_for(resource)
      else
        handle_failed_account_update
      end
    end

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

    def configure_account_update_params
      devise_parameter_sanitizer.permit(
        :account_update,
        keys: %i[name password password_confirmation current_password]
      )
    end

    def update_resource(resource, params)
      params = params.except(:email)
      if password_change_requested?(params)
        resource.update_with_password(params)
      else
        resource.update_without_password(
          params.except(:password, :password_confirmation, :current_password)
        )
      end
    end

    def password_change_requested?(params)
      params[:password].present? || params[:password_confirmation].present?
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

    def handle_failed_account_update
      clean_up_passwords resource
      set_minimum_password_length
      render :edit, status: :unprocessable_entity
    end

    def handle_failed_sign_up
      clean_up_passwords resource
      set_minimum_password_length
      render :new, status: :unprocessable_entity
    end

    def after_update_path_for(resource)
      consume_workspace_return_to || workshop_resume_path || super
    end

    def after_sign_up_path_for(resource)
      consume_workspace_return_to || workshop_resume_path || super
    end

    def after_inactive_sign_up_path_for(resource)
      consume_workspace_return_to || workshop_resume_path || super
    end
  end
end
