module ApplicationHelper
  include UiHelper
  include NestingPreviewHelper

  def sheet_stock_dimension_mm(value)
    number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
  end

  def sheet_stock_quantity_label(stock)
    stock.quantity.present? ? stock.quantity.to_s : t("projects.form.quantity_unlimited")
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
