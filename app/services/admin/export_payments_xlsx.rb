# frozen_string_literal: true

require "axlsx"

module Admin
  class ExportPaymentsXlsx
    DETAIL_HEADERS = [
      "ID", "Fecha y Hora", "Usuario ID", "Email Comprador", "Nombre Comprador",
      "Identificación SINPE", "Teléfono SINPE", "Referencia de Compra",
      "ID Intento de Pago (ONVO)", "Método de Pago", "Estado",
      "Monto Lista", "Descuento", "Subtotal", "Impuesto (IVA 13%)",
      "Total Cobrado", "Moneda", "Código CAByS"
    ].freeze

    SUMMARY_HEADERS = [
      "Fecha (Día)", "Moneda", "Método de Pago",
      "Cantidad de Ventas", "Total Precio Lista", "Total Descuento",
      "Total Subtotal (Base Imponible)", "Total IVA 13%", "Total Neto Cobrado"
    ].freeze

    HEADER_STYLE_COLOR = "1E3A5F".freeze
    ACCENT_COLOR       = "2A4D7A".freeze
    STRIPE_COLOR       = "F0F3F7".freeze

    DETAIL_TYPES = [
      :string, nil, :string, :string, :string, :string, :string, :string, :string,
      :string, :string, :float, :float, :float, :float, :float, :string, :string
    ].freeze

    def self.call(payments, direction: "desc")
      package = Axlsx::Package.new
      wb = package.workbook
      styles = build_styles(wb)

      add_detail_sheet(wb, payments.where(currency: "crc"), direction:, styles:, sheet_name: "Detalle CRC")
      add_detail_sheet(wb, payments.where(currency: "usd"), direction:, styles:, sheet_name: "Detalle USD Export")
      add_summary_sheet(wb, payments, currency: "crc", direction:, styles:, sheet_name: "Resumen Hacienda CRC")
      add_summary_sheet(wb, payments, currency: "usd", direction:, styles:, sheet_name: "Resumen Hacienda USD")

      package.to_stream.read
    end

    def self.build_styles(wb)
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
    private_class_method :build_styles

    def self.add_detail_sheet(wb, payments, direction:, styles:, sheet_name:)
      sorted_payments = payments.order(created_at: direction.to_sym)

      wb.add_worksheet(name: sheet_name) do |sheet|
        sheet.add_row DETAIL_HEADERS, style: styles.fetch(:header), height: 32

        sorted_payments.each_with_index do |p, idx|
          stripe = idx.odd?
          row_plain = stripe ? styles.fetch(:stripe) : styles.fetch(:plain)
          row_money = stripe ? styles.fetch(:money_stripe) : styles.fetch(:money)
          row_date  = stripe ? styles.fetch(:date_stripe) : styles.fetch(:date)
          actual_total = p.total_amount.to_f > 0 ? p.total_amount.to_f : p.amount.to_f

          sheet.add_row(
            detail_row_values(p, actual_total),
            types: DETAIL_TYPES,
            style: detail_row_styles(row_plain, row_date, row_money),
            height: 20
          )
        end

        sheet.column_widths 8, 18, 10, 28, 24, 20, 14, 16, 28, 16, 12, 12, 12, 12, 12, 12, 9, 18
        sheet.sheet_view.show_grid_lines = true
      end
    end
    private_class_method :add_detail_sheet

    def self.add_summary_sheet(wb, payments, currency:, direction:, styles:, sheet_name:)
      succeeded = payments.where(status: "succeeded", currency: currency)
      grouped = succeeded.group_by do |p|
        date_str = p.created_at.in_time_zone("America/Costa_Rica").to_date.to_s
        [ date_str, p.payment_method ]
      end

      sorted_keys = grouped.keys.sort_by { |k| [ k[0], k[1] ] }
      sorted_keys = sorted_keys.reverse if direction == "desc"

      wb.add_worksheet(name: sheet_name) do |sheet|
        sheet.add_row SUMMARY_HEADERS, style: styles.fetch(:summary_header), height: 32

        sorted_keys.each_with_index do |key, idx|
          stripe = idx.odd?
          row_plain = stripe ? styles.fetch(:stripe) : styles.fetch(:plain)
          row_money = stripe ? styles.fetch(:money_stripe) : styles.fetch(:money)
          date_str, method = key
          group = grouped.fetch(key)

          sheet.add_row(
            summary_row_values(date_str, currency, method, group),
            types: [ :string, :string, :string, :integer, :float, :float, :float, :float, :float ],
            style: [ row_plain, row_plain, row_plain, row_plain, row_money, row_money, row_money, row_money, row_money ],
            height: 20
          )
        end

        sheet.add_row(
          summary_totals_row(sorted_keys, grouped, currency),
          types: [ :string, :string, :string, :integer, :float, :float, :float, :float, :float ],
          style: [
            styles.fetch(:totals_label), styles.fetch(:totals_label), styles.fetch(:totals_label),
            styles.fetch(:totals),
            styles.fetch(:totals_money), styles.fetch(:totals_money), styles.fetch(:totals_money),
            styles.fetch(:totals_money), styles.fetch(:totals_money)
          ],
          height: 24
        )

        sheet.column_widths 14, 9, 16, 14, 18, 16, 24, 16, 18
        sheet.sheet_view.show_grid_lines = true
      end
    end
    private_class_method :add_summary_sheet

    def self.detail_row_values(payment, actual_total)
      [
        payment.id.to_s,
        payment.created_at.in_time_zone("America/Costa_Rica"),
        payment.user_id.to_s,
        payment.purchaser_email.to_s,
        payment.purchaser_name.to_s,
        payment.sinpe_transfer_identification.to_s,
        payment.sinpe_transfer_mobile_number.to_s,
        payment.purchase_reference.to_s,
        payment.onvo_payment_intent_id.to_s,
        payment_method_label(payment.payment_method),
        status_label(payment.status),
        payment.list_price.to_f,
        payment.discount_amount.to_f,
        payment.subtotal.to_f,
        payment.tax_amount.to_f,
        actual_total,
        payment.currency.to_s.upcase,
        payment.cabys_code.to_s
      ]
    end
    private_class_method :detail_row_values

    def self.detail_row_styles(row_plain, row_date, row_money)
      [
        row_plain, row_date, row_plain, row_plain, row_plain, row_plain, row_plain,
        row_plain, row_plain, row_plain, row_plain, row_money, row_money, row_money,
        row_money, row_money, row_plain, row_plain
      ]
    end
    private_class_method :detail_row_styles

    def self.summary_row_values(date_str, currency, method, group)
      [
        date_str,
        currency.to_s.upcase,
        payment_method_label(method),
        group.size,
        group.sum { |p| p.list_price.to_f }.round(2),
        group.sum { |p| p.discount_amount.to_f }.round(2),
        group.sum { |p| p.subtotal.to_f }.round(2),
        group.sum { |p| p.tax_amount.to_f }.round(2),
        group.sum { |p| p.total_amount.to_f > 0 ? p.total_amount.to_f : p.amount.to_f }.round(2)
      ]
    end
    private_class_method :summary_row_values

    def self.summary_totals_row(sorted_keys, grouped, currency)
      [
        "TOTAL #{currency.to_s.upcase}",
        currency.to_s.upcase,
        "—",
        sorted_keys.sum { |k| grouped.fetch(k).size },
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| p.list_price.to_f } }.round(2),
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| p.discount_amount.to_f } }.round(2),
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| p.subtotal.to_f } }.round(2),
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| p.tax_amount.to_f } }.round(2),
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p|
          p.total_amount.to_f > 0 ? p.total_amount.to_f : p.amount.to_f
        } }.round(2)
      ]
    end
    private_class_method :summary_totals_row

    def self.payment_method_label(method)
      case method.to_s
      when "card_crc"  then "Tarjeta CRC"
      when "card_usd"  then "Tarjeta USD"
      when "sinpe_crc" then "SINPE Móvil"
      else method.to_s.upcase.tr("_", " ")
      end
    end

    def self.status_label(status)
      case status.to_s
      when "succeeded" then "Exitoso"
      when "pending"   then "Pendiente"
      when "failed"    then "Fallido"
      else status.to_s.capitalize
      end
    end
  end
end
