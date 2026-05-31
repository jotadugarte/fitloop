# frozen_string_literal: true

require "csv"

module Admin
  class ExportPaymentsCsv
    def self.call(payments)
      csv_string = CSV.generate(headers: true) do |csv|
        csv << [
          "ID", "Fecha", "Usuario ID", "Email Comprador", "Nombre Comprador",
          "Identificación SINPE", "Teléfono SINPE", "Referencia", "ID Intento de Pago",
          "Método de Pago", "Estado", "Monto Lista", "Descuento", "Subtotal",
          "Impuesto (IVA)", "Monto Total", "Moneda", "Código CAByS"
        ]

        payments.each do |p|
          csv << [
            p.id,
            p.created_at,
            p.user_id,
            p.purchaser_email,
            p.purchaser_name,
            format_excel_text(p.sinpe_transfer_identification),
            format_excel_text(p.sinpe_transfer_mobile_number),
            format_excel_text(p.purchase_reference),
            format_excel_text(p.onvo_payment_intent_id),
            p.payment_method,
            p.status,
            p.list_price.to_f,
            p.discount_amount.to_f,
            p.subtotal.to_f,
            p.tax_amount.to_f,
            p.total_amount.to_f,
            p.currency,
            format_excel_text(p.cabys_code)
          ]
        end
      end

      "\uFEFF" + csv_string
    end

    def self.format_excel_text(val)
      return "" if val.blank?
      "=\"#{val}\""
    end
  end
end
