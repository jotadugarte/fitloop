# frozen_string_literal: true

require "csv"

module Admin
  class ExportSummaryCsv
    def self.call(payments)
      # Filter for succeeded payments since only succeeded payments are relevant to tax declaration
      succeeded_payments = payments.where(status: "succeeded")

      # Group by date (in America/Costa_Rica timezone), currency, and payment method
      grouped = succeeded_payments.group_by do |p|
        date_str = p.created_at.in_time_zone("America/Costa_Rica").to_date.to_s
        [date_str, p.currency, p.payment_method]
      end

      csv_string = CSV.generate(headers: true) do |csv|
        csv << [
          "Fecha (Día)",
          "Moneda",
          "Método de Pago",
          "Cantidad de Ventas",
          "Total Precio Lista",
          "Total Descuento",
          "Total Subtotal (Base)",
          "Total Impuesto (IVA 13%)",
          "Total Neto Cobrado"
        ]

        # Sort chronologically by date, then currency, then payment method
        grouped.keys.sort_by { |k| [k[0], k[1], k[2]] }.each do |key|
          date_str, currency, payment_method = key
          group_payments = grouped[key]

          count = group_payments.size
          sum_list = group_payments.sum { |p| p.list_price.to_f }
          sum_discount = group_payments.sum { |p| p.discount_amount.to_f }
          sum_subtotal = group_payments.sum { |p| p.subtotal.to_f }
          sum_tax = group_payments.sum { |p| p.tax_amount.to_f }
          sum_total = group_payments.sum { |p| p.total_amount.to_f > 0 ? p.total_amount.to_f : p.amount.to_f }

          csv << [
            date_str,
            currency.to_s.upcase,
            payment_method.to_s.upcase.gsub('_', ' '),
            count,
            sum_list.round(2),
            sum_discount.round(2),
            sum_subtotal.round(2),
            sum_tax.round(2),
            sum_total.round(2)
          ]
        end
      end

      "\uFEFF" + csv_string
    end
  end
end
