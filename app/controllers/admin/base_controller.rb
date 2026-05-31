# frozen_string_literal: true

# [REQ-FIT-ADMIN-001] Base controller for all /admin/* routes.
# Returns 404 for non-admin and unauthenticated requests — does NOT redirect
# to login, to avoid leaking the existence of the admin interface.
module Admin
  class BaseController < ApplicationController
    layout "admin"
    before_action :require_admin!

    private

    def require_admin!
      raise ActionController::RoutingError, "Not Found" unless admin_user?
    end

    def admin_user?
      user_signed_in? && current_user.admin?
    end
  end
end
