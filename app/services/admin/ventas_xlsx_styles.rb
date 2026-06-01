# frozen_string_literal: true

module Admin
  # Shared Axlsx styles for admin ventas XLSX exports.
  class VentasXlsxStyles
    HEADER_STYLE_COLOR = "1E3A5F"
    ACCENT_COLOR       = "2A4D7A"
    STRIPE_COLOR       = "F0F3F7"

    def self.build(wb)
      {
        header: wb.styles.add_style(
          bg_color: HEADER_STYLE_COLOR, fg_color: "FFFFFF", b: true, sz: 10,
          alignment: { wrap_text: true, horizontal: :center, vertical: :center },
          border: { style: :thin, color: "FFFFFF" }
        ),
        summary_header: wb.styles.add_style(
          bg_color: ACCENT_COLOR, fg_color: "FFFFFF", b: true, sz: 10,
          alignment: { wrap_text: true, horizontal: :center, vertical: :center },
          border: { style: :thin, color: "FFFFFF" }
        ),
        stripe: wb.styles.add_style(bg_color: STRIPE_COLOR, sz: 10, alignment: { vertical: :center }),
        plain: wb.styles.add_style(sz: 10, alignment: { vertical: :center }),
        money: wb.styles.add_style(sz: 10, format_code: "#,##0.00", alignment: { horizontal: :right, vertical: :center }),
        money_stripe: wb.styles.add_style(
          sz: 10, bg_color: STRIPE_COLOR, format_code: "#,##0.00",
          alignment: { horizontal: :right, vertical: :center }
        ),
        date: wb.styles.add_style(sz: 10, format_code: "DD/MM/YYYY HH:MM", alignment: { vertical: :center }),
        date_stripe: wb.styles.add_style(
          sz: 10, bg_color: STRIPE_COLOR, format_code: "DD/MM/YYYY HH:MM", alignment: { vertical: :center }
        ),
        totals: wb.styles.add_style(
          bg_color: HEADER_STYLE_COLOR, fg_color: "FFFFFF", b: true, sz: 10,
          alignment: { horizontal: :right, vertical: :center }, border: { style: :thin, color: "FFFFFF" }
        ),
        totals_label: wb.styles.add_style(
          bg_color: HEADER_STYLE_COLOR, fg_color: "FFFFFF", b: true, sz: 10,
          alignment: { horizontal: :center, vertical: :center }, border: { style: :thin, color: "FFFFFF" }
        ),
        totals_money: wb.styles.add_style(
          bg_color: HEADER_STYLE_COLOR, fg_color: "FFFFFF", b: true, sz: 10, format_code: "#,##0.00",
          alignment: { horizontal: :right, vertical: :center }, border: { style: :thin, color: "FFFFFF" }
        )
      }
    end
  end
end
