require "csv"

module Admin
  class DashboardController < Admin::BaseController
    def index
      @payments = Payment.order(created_at: :desc).limit(25)
      @total_revenue_crc = Payment.where(status: "succeeded", currency: "crc").sum("COALESCE(NULLIF(total_amount, 0), amount)")
      @total_revenue_usd = Payment.where(status: "succeeded", currency: "usd").sum("COALESCE(NULLIF(total_amount, 0), amount)")
      @succeeded_count = Payment.where(status: "succeeded").count
      @failed_count = Payment.where(status: "failed").count
      @pending_count = Payment.where(status: "pending").count

      @total_users = User.count
      @recent_users = User.order(created_at: :desc).limit(5)

      @total_nesting_runs = NestingRun.count
      @recent_runs = NestingRun.order(created_at: :desc).limit(5)
    end

    def export_payments
      payments = Payment.order(created_at: :desc)
      csv_data = CSV.generate(headers: true) do |csv|
        csv << [
          "ID", "Fecha", "Usuario ID", "Email Comprador", "Nombre Comprador",
          "Concepto", "Metodo de Pago", "Moneda", "Subtotal", "Descuento",
          "Impuesto", "Total", "Estado", "Referencia", "Identificacion SINPE"
        ]

        payments.each do |p|
          csv << [
            p.id, p.created_at, p.user_id, p.purchaser_email, p.purchaser_name,
            p.purpose, p.payment_method, p.currency, p.subtotal.to_f, p.discount_amount.to_f,
            p.tax_amount.to_f, p.total_amount.to_f, p.status, p.purchase_reference, p.sinpe_transfer_identification
          ]
        end
      end

      send_data csv_data, filename: "ventas-fitloop-#{Time.current.strftime('%Y-%m-%d')}.csv", type: "text/csv"
    end
  end
end
