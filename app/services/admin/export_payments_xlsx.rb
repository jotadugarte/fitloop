# frozen_string_literal: true

require "axlsx"

module Admin
  class ExportPaymentsXlsx
    DETAIL_HEADERS = [
      "ID", "Fecha y Hora", "Usuario ID", "Email Comprador", "Nombre Comprador", "Concepto",
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

    DETAIL_TYPES = [
      :string, nil, :string, :string, :string, :string, :string, :string, :string, :string,
      :string, :string, :float, :float, :float, :float, :float, :string, :string
    ].freeze

    def self.call(payments, direction: "desc")
      package = Axlsx::Package.new
      wb = package.workbook
      styles = VentasXlsxStyles.build(wb)

      add_detail_sheet(wb, payments.where(currency: "crc"), direction:, styles:, sheet_name: "Detalle CRC")
      add_detail_sheet(wb, payments.where(currency: "usd"), direction:, styles:, sheet_name: "Detalle USD Export")
      add_summary_sheet(wb, payments, currency: "crc", direction:, styles:, sheet_name: "Resumen Hacienda CRC")
      add_summary_sheet(wb, payments, currency: "usd", direction:, styles:, sheet_name: "Resumen Hacienda USD")

      package.to_stream.read
    end

    def self.add_detail_sheet(wb, payments, direction:, styles:, sheet_name:)
      sorted_payments = payments.order(created_at: direction.to_sym)

      wb.add_worksheet(name: sheet_name) do |sheet|
        sheet.add_row DETAIL_HEADERS, style: styles.fetch(:header), height: 32

        sorted_payments.each_with_index do |p, idx|
          stripe = idx.odd?
          row_plain = stripe ? styles.fetch(:stripe) : styles.fetch(:plain)
          row_money = stripe ? styles.fetch(:money_stripe) : styles.fetch(:money)
          row_date  = stripe ? styles.fetch(:date_stripe) : styles.fetch(:date)
          actual_total = HaciendaSummaryRows.net_collected(p)

          sheet.add_row(
            detail_row_values(p, actual_total),
            types: DETAIL_TYPES,
            style: detail_row_styles(row_plain, row_date, row_money),
            height: 20
          )
        end

        sheet.column_widths 8, 18, 10, 28, 24, 32, 20, 14, 16, 28, 16, 12, 12, 12, 12, 12, 12, 9, 18
        sheet.sheet_view.show_grid_lines = true
      end
    end
    private_class_method :add_detail_sheet

    def self.add_summary_sheet(wb, payments, currency:, direction:, styles:, sheet_name:)
      grouped = HaciendaSummaryRows.succeeded_groups(payments, currency: currency)
      sorted_keys = HaciendaSummaryRows.sorted_keys(grouped, direction: direction)

      wb.add_worksheet(name: sheet_name) do |sheet|
        sheet.add_row SUMMARY_HEADERS, style: styles.fetch(:summary_header), height: 32

        sorted_keys.each_with_index do |key, idx|
          stripe = idx.odd?
          row_plain = stripe ? styles.fetch(:stripe) : styles.fetch(:plain)
          row_money = stripe ? styles.fetch(:money_stripe) : styles.fetch(:money)
          date_str, payment_method = key
          group = grouped.fetch(key)

          sheet.add_row(
            HaciendaSummaryRows.row_values(date_str, currency, payment_method, group),
            types: [ :string, :string, :string, :integer, :float, :float, :float, :float, :float ],
            style: [ row_plain, row_plain, row_plain, row_plain, row_money, row_money, row_money, row_money, row_money ],
            height: 20
          )
        end

        sheet.add_row(
          HaciendaSummaryRows.totals_row(sorted_keys, grouped, currency),
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
        payment.created_at.in_time_zone(HaciendaSummaryRows::CR_ZONE),
        payment.user_id.to_s,
        payment.purchaser_email.to_s,
        payment.purchaser_name.to_s,
        PaymentDisplayLabels.product_label(payment),
        payment.sinpe_transfer_identification.to_s,
        payment.sinpe_transfer_mobile_number.to_s,
        payment.purchase_reference.to_s,
        payment.onvo_payment_intent_id.to_s,
        PaymentDisplayLabels.payment_method_label(payment.payment_method),
        PaymentDisplayLabels.status_label(payment.status),
        payment.list_price.to_f,
        payment.discount_amount.to_f,
        payment.subtotal.to_f,
        payment.tax_amount.to_f,
        actual_total,
        payment.currency.to_s.upcase,
        payment.cabys_code.presence || Payment::DEFAULT_CABYS_CODE
      ]
    end
    private_class_method :detail_row_values

    def self.detail_row_styles(row_plain, row_date, row_money)
      [
        row_plain, row_date, row_plain, row_plain, row_plain, row_plain, row_plain, row_plain,
        row_plain, row_plain, row_plain, row_plain, row_money, row_money, row_money,
        row_money, row_money, row_plain, row_plain
      ]
    end
    private_class_method :detail_row_styles
  end
end
