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

      succeeded = payments.where(status: "succeeded", currency: currency)
      grouped = succeeded.group_by do |p|
        date_str = p.created_at.in_time_zone("America/Costa_Rica").to_date.to_s
        [ date_str, p.payment_method ]
      end

      sorted_keys = grouped.keys.sort_by { |k| [ k[0], k[1] ] }
      sorted_keys = sorted_keys.reverse if direction == "desc"

      sorted_keys.each do |key|
        date_str, payment_method = key
        group_payments = grouped.fetch(key)

        csv << [
          date_str,
          currency.to_s.upcase,
          payment_method.to_s.upcase.tr("_", " "),
          group_payments.size,
          group_payments.sum { |p| p.list_price.to_f }.round(2),
          group_payments.sum { |p| p.discount_amount.to_f }.round(2),
          group_payments.sum { |p| p.subtotal.to_f }.round(2),
          group_payments.sum { |p| p.tax_amount.to_f }.round(2),
          group_payments.sum { |p| p.total_amount.to_f > 0 ? p.total_amount.to_f : p.amount.to_f }.round(2)
        ]
      end

      csv << totals_row(sorted_keys, grouped, currency)
    end
    private_class_method :append_currency_section

    def self.totals_row(sorted_keys, grouped, currency)
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
    private_class_method :totals_row
  end
end
