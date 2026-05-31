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

    # Cell types for the detail sheet — matches the values array position.
    # :string forces Excel to treat numeric-looking values as text,
    # preventing scientific/exponential notation on long digit sequences.
    DETAIL_TYPES = [
      :string,  # id              (forced text — no thousands separator)
      nil,      # created_at      (caxlsx auto-detects ActiveSupport::TimeWithZone)
      :string,  # user_id         (forced text)
      :string,  # purchaser_email
      :string,  # purchaser_name
      :string,  # sinpe_transfer_identification  ← was 2.34E+11
      :string,  # sinpe_transfer_mobile_number   ← was 8.89E+07
      :string,  # purchase_reference             ← was 8.05E+11
      :string,  # onvo_payment_intent_id         ← was 7.10E+10
      :string,  # payment_method label
      :string,  # status label
      :float,   # list_price
      :float,   # discount_amount
      :float,   # subtotal
      :float,   # tax_amount
      :float,   # total_amount
      :string,  # currency
      :string   # cabys_code                     ← was 8.31E+12
    ].freeze

    def self.call(payments, direction: "desc")
      package = Axlsx::Package.new
      wb = package.workbook

      header_style = wb.styles.add_style(
        bg_color: HEADER_STYLE_COLOR,
        fg_color: "FFFFFF",
        b: true,
        sz: 10,
        alignment: { wrap_text: true, horizontal: :center, vertical: :center },
        border: { style: :thin, color: "FFFFFF" }
      )

      stripe_style = wb.styles.add_style(
        bg_color: STRIPE_COLOR,
        sz: 10,
        alignment: { vertical: :center }
      )

      plain_style = wb.styles.add_style(
        sz: 10,
        alignment: { vertical: :center }
      )

      money_style = wb.styles.add_style(
        sz: 10,
        format_code: "#,##0.00",
        alignment: { horizontal: :right, vertical: :center }
      )

      money_stripe_style = wb.styles.add_style(
        sz: 10,
        bg_color: STRIPE_COLOR,
        format_code: "#,##0.00",
        alignment: { horizontal: :right, vertical: :center }
      )

      date_style = wb.styles.add_style(
        sz: 10,
        format_code: "DD/MM/YYYY HH:MM",
        alignment: { vertical: :center }
      )

      date_stripe_style = wb.styles.add_style(
        sz: 10,
        bg_color: STRIPE_COLOR,
        format_code: "DD/MM/YYYY HH:MM",
        alignment: { vertical: :center }
      )

      summary_header_style = wb.styles.add_style(
        bg_color: ACCENT_COLOR,
        fg_color: "FFFFFF",
        b: true,
        sz: 10,
        alignment: { wrap_text: true, horizontal: :center, vertical: :center },
        border: { style: :thin, color: "FFFFFF" }
      )

      # ── Sheet 1: Detalle de Transacciones ─────────────────────────────────
      sorted_payments = payments.order(created_at: direction.to_sym)

      wb.add_worksheet(name: "Detalle Transacciones") do |sheet|
        sheet.add_row DETAIL_HEADERS, style: header_style, height: 32

        sorted_payments.each_with_index do |p, idx|
          stripe = idx.odd?
          row_plain = stripe ? stripe_style      : plain_style
          row_money = stripe ? money_stripe_style : money_style
          row_date  = stripe ? date_stripe_style  : date_style

          actual_total = p.total_amount.to_f > 0 ? p.total_amount.to_f : p.amount.to_f

          sheet.add_row(
            [
              p.id.to_s,
              p.created_at.in_time_zone("America/Costa_Rica"),
              p.user_id.to_s,
              p.purchaser_email.to_s,
              p.purchaser_name.to_s,
              p.sinpe_transfer_identification.to_s,
              p.sinpe_transfer_mobile_number.to_s,
              p.purchase_reference.to_s,
              p.onvo_payment_intent_id.to_s,
              payment_method_label(p.payment_method),
              status_label(p.status),
              p.list_price.to_f,
              p.discount_amount.to_f,
              p.subtotal.to_f,
              p.tax_amount.to_f,
              actual_total,
              p.currency.to_s.upcase,
              p.cabys_code.to_s
            ],
            types: DETAIL_TYPES,
            style: [
              row_plain, row_date,  row_plain, row_plain, row_plain,
              row_plain, row_plain, row_plain, row_plain, row_plain,
              row_plain, row_money, row_money, row_money, row_money,
              row_money, row_plain, row_plain
            ],
            height: 20
          )
        end

        # Column widths (approximate best-fit)
        sheet.column_widths 8, 18, 10, 28, 24, 20, 14, 16, 28, 16, 12,
                            12, 12, 12, 12, 12, 9, 18

        sheet.sheet_view.show_grid_lines = true
      end

      # ── Sheet 2: Resumen Hacienda ──────────────────────────────────────────
      succeeded = payments.where(status: "succeeded")

      grouped = succeeded.group_by do |p|
        date_str = p.created_at.in_time_zone("America/Costa_Rica").to_date.to_s
        [ date_str, p.currency, p.payment_method ]
      end

      sorted_keys = grouped.keys.sort_by { |k| [ k[0], k[1], k[2] ] }
      sorted_keys = sorted_keys.reverse if direction == "desc"

      wb.add_worksheet(name: "Resumen Hacienda") do |sheet|
        sheet.add_row SUMMARY_HEADERS, style: summary_header_style, height: 32

        sorted_keys.each_with_index do |key, idx|
          stripe = idx.odd?
          row_plain = stripe ? stripe_style      : plain_style
          row_money = stripe ? money_stripe_style : money_style

          date_str, currency, method = key
          group = grouped[key]

          count        = group.size
          sum_list     = group.sum { |p| p.list_price.to_f }.round(2)
          sum_discount = group.sum { |p| p.discount_amount.to_f }.round(2)
          sum_subtotal = group.sum { |p| p.subtotal.to_f }.round(2)
          sum_tax      = group.sum { |p| p.tax_amount.to_f }.round(2)
          sum_total    = group.sum { |p|
            p.total_amount.to_f > 0 ? p.total_amount.to_f : p.amount.to_f
          }.round(2)

          sheet.add_row(
            [
              date_str,
              currency.to_s.upcase,
              payment_method_label(method),
              count,
              sum_list,
              sum_discount,
              sum_subtotal,
              sum_tax,
              sum_total
            ],
            types: [ :string, :string, :string, :integer,
                     :float,  :float,  :float,  :float,  :float ],
            style: [
              row_plain, row_plain, row_plain, row_plain,
              row_money, row_money, row_money, row_money, row_money
            ],
            height: 20
          )
        end

        sheet.column_widths 14, 9, 16, 14, 18, 16, 24, 16, 18
        sheet.sheet_view.show_grid_lines = true
      end

      package.to_stream.read
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

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
