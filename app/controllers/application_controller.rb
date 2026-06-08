class ApplicationController < ActionController::Base
  include WorkshopUrlHelper
  include LocaleSwitchable
  include ResolvesWorkspaceTab
  include StoresWorkspaceReturnTo
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  layout :layout_for_controller

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  before_action :check_maintenance_mode
  before_action :set_anonymous_session_key

  def after_sign_in_path_for(resource)
    if resource.is_a?(User)
      Billing::CartMergeOnLogin.call(user: resource, guest_token: session[:cart_guest_token])
      Analytics::MergeAnonymousSession.call(session[:anonymous_session_key], resource.id)
      session.delete(:cart_guest_token)
      session.delete(:pending_cart)
    end

    super
  end

  private

  def set_anonymous_session_key
    session[:anonymous_session_key] ||= SecureRandom.hex(16)
  end

  def layout_for_controller
    devise_controller? ? "minimal" : "application"
  end

  # [REQ-FIT-QA-001] Checks if maintenance mode is enabled and intercepts requests unless bypassed
  def check_maintenance_mode
    return unless ENV["MAINTENANCE_MODE"] == "true"

    # Bypass conditions
    return if request.path == "/up"
    return if request.path.start_with?("/assets/") || request.path.start_with?("/rails/active_storage/")
    return if devise_controller?
    return if current_user&.admin?

    render template: "errors/maintenance", layout: "minimal", status: :service_unavailable
  end
end
