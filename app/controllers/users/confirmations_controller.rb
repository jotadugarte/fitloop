# frozen_string_literal: true

module Users
  # [REQ-FIT-AUTH-002] Resend confirmation; pre-fill email when already signed in.
  class ConfirmationsController < Devise::ConfirmationsController
    def new
      self.resource = resource_class.new
      resource.email = current_user.email if user_signed_in?
    end
  end
end
