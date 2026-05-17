module ApplicationHelper
  include UiHelper
  include NestingPreviewHelper

  def sheet_stock_summary(stock)
    quantity_label =
      if stock.quantity.present?
        stock.quantity.to_s
      else
        t("projects.form.quantity_unlimited")
      end

    t(
      "projects.form.sheet_summary",
      width: number_with_precision(stock.width_mm, precision: 1, strip_insignificant_zeros: true),
      height: number_with_precision(stock.height_mm, precision: 1, strip_insignificant_zeros: true),
      quantity: quantity_label
    )
  end
end
