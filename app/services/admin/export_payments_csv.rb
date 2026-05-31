# frozen_string_literal: true

require "csv"

module Admin
  class ExportPaymentsCsv
    def self.call(payments)
      CSV.generate(headers: true) do |csv|
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
            p.sinpe_transfer_identification,
            p.sinpe_transfer_mobile_number,
            p.purchase_reference,
            p.onvo_payment_intent_id,
            p.payment_method,
            p.status,
            p.list_price.to_f,
            p.discount_amount.to_f,
            p.subtotal.to_f,
            p.tax_amount.to_f,
            p.total_amount.to_f,
            p.currency,
            p.cabys_code
          ]
        end
      end
    end
  end
end
