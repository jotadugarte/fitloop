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
  end
end
