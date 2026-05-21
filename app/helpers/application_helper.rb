module ApplicationHelper
  include NestingProgressHelper
  include UiHelper
  include NestingPreviewHelper

  def user_omniauth_authorize_path(provider)
    public_send(Auth::OmniauthProviders.authorize_path_name(provider).to_sym)
  end

  def auth_back_path
    session[:workspace_return_to].presence || root_path
  end

  def auth_back_label
    session[:workspace_return_to].present? ? t("auth.nav.back") : t("auth.nav.home")
  end

  def sheet_stock_dimension_mm(value)
    number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
  end

  def nesting_mm_value(value)
    formatted = number_with_precision(value, precision: 2, strip_insignificant_zeros: true)
    t("projects.show.nesting_value_mm", value: formatted)
  end

  def sheet_stock_quantity_label(stock)
    stock.quantity.present? ? stock.quantity.to_s : t("projects.form.quantity_unlimited")
  end

  def sheet_stock_consumption_priority_label(stock)
    "##{stock.sort_order.to_i + 1}"
  end

  def sheet_stock_summary(stock)
    t(
      "projects.form.sheet_summary",
      width: sheet_stock_dimension_mm(stock.width_mm),
      height: sheet_stock_dimension_mm(stock.height_mm),
      quantity: sheet_stock_quantity_label(stock)
    )
  end
end
