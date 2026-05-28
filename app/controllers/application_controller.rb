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

  def after_sign_in_path_for(resource)
    if resource.is_a?(User)
      Billing::CartMergeOnLogin.call(user: resource, guest_token: session[:cart_guest_token])
      session.delete(:cart_guest_token)
    end

    super
  end

  private

  def layout_for_controller
    devise_controller? ? "minimal" : "application"
  end
end
