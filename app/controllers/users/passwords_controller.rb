# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] Password reset with 12-char minimum and Spanish redirects.
  class PasswordsController < Devise::PasswordsController
    def create
      self.resource = resource_class.send_reset_password_instructions(resource_params)

      if successfully_sent?(resource)
        redirect_to new_user_session_path, notice: t("auth.password.reset_sent")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def update
      self.resource = resource_class.reset_password_by_token(resource_params)

      if resource.errors.empty?
        redirect_to new_user_session_path, notice: t("auth.password.updated")
      else
        set_minimum_password_length
        render :edit, status: :unprocessable_entity
      end
    end
  end
end
