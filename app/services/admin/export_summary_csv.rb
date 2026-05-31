# frozen_string_literal: true

require "csv"

module Admin
  class ExportSummaryCsv
    SUMMARY_HEADERS = [
      "Fecha (Día)",
      "Moneda",
      "Método de Pago",
      "Cantidad de Ventas",
      "Total Precio Lista",
      "Total Descuento",
      "Total Subtotal (Base)",
      "Total Impuesto (IVA 13%)",
      "Total Neto Cobrado"
    ].freeze

    def self.call(payments, direction: "desc")
      csv_string = CSV.generate do |csv|
        append_currency_section(csv, payments, currency: "crc", title: "DECLARACIÓN CRC — VENTAS LOCALES (IVA 13%)", direction:)
        csv << []
        append_currency_section(csv, payments, currency: "usd", title: "DECLARACIÓN USD — FACTURA DE EXPORTACIÓN", direction:)
      end

      "\uFEFF" + csv_string
    end

    def self.append_currency_section(csv, payments, currency:, title:, direction:)
      csv << [ title ]
      csv << SUMMARY_HEADERS

      grouped = HaciendaSummaryRows.succeeded_groups(payments, currency: currency)
      sorted_keys = HaciendaSummaryRows.sorted_keys(grouped, direction: direction)

      sorted_keys.each do |key|
        date_str, payment_method = key
        group = grouped.fetch(key)
        csv << HaciendaSummaryRows.row_values(date_str, currency, payment_method, group)
      end

      csv << HaciendaSummaryRows.totals_row(sorted_keys, grouped, currency)
    end
    private_class_method :append_currency_section
  end
end
