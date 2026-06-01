# frozen_string_literal: true

module Admin
  module VentasHelper
    def admin_payment_method_label(method)
      Admin::PaymentDisplayLabels.payment_method_label(method)
    end

    def admin_payment_status_label(status)
      Admin::PaymentDisplayLabels.status_label(status)
    end

    def admin_payment_purpose_label(purpose)
      Admin::PaymentDisplayLabels.purpose_label(purpose)
    end

    def admin_payment_product_label(payment)
      Admin::PaymentDisplayLabels.product_label(payment)
    end

    def admin_payment_net_collected(payment)
      Admin::HaciendaSummaryRows.net_collected(payment)
    end

    def admin_form150_export_params(query_params)
      Admin::VentasFilter.normalize_form150_export_params(query_params)
    end
  end
end
