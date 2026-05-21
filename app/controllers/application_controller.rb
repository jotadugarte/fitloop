class ApplicationController < ActionController::Base
  include LocaleSwitchable
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  layout :layout_for_controller

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  private

  def layout_for_controller
    devise_controller? ? "minimal" : "application"
  end
end
