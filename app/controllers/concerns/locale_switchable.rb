# frozen_string_literal: true

# [REQ-FIT-UI-005] Resolve locale from params, cookie, or session; persist on switch.
module LocaleSwitchable
  extend ActiveSupport::Concern

  LOCALE_COOKIE = :fitloop_locale

  included do
    before_action :set_locale
  end

  def persist_locale!(locale)
    cookies.permanent[LOCALE_COOKIE] = locale.to_s
    session[:locale] = locale.to_s
  end

  private

  def set_locale
    I18n.locale = resolve_locale
  end

  def resolve_locale
    candidate = params[:locale].presence || cookies[LOCALE_COOKIE].presence || session[:locale]
    return I18n.default_locale if candidate.blank?

    sym = candidate.to_sym
    I18n.available_locales.include?(sym) ? sym : I18n.default_locale
  end
end
