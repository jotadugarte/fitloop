# frozen_string_literal: true

module Admin
  # [REQ-FIT-ADMIN-001] Spanish labels for admin ventas UI and exports.
  module PaymentDisplayLabels
    PAYMENT_METHOD_LABELS = {
      "card_crc" => "Tarjeta CRC",
      "card_usd" => "Tarjeta USD",
      "sinpe_crc" => "SINPE Móvil"
    }.freeze

    STATUS_LABELS = {
      "succeeded" => "Exitoso",
      "pending" => "Pendiente",
      "failed" => "Fallido"
    }.freeze

    PURPOSE_LABELS = {
      "single_download" => "Descarga suelta",
      "plan_subscription" => "Plan"
    }.freeze

    def self.payment_method_label(method)
      PAYMENT_METHOD_LABELS.fetch(method.to_s) do
        method.to_s.upcase.tr("_", " ")
      end
    end

    def self.status_label(status)
      STATUS_LABELS.fetch(status.to_s) do
        status.to_s.capitalize
      end
    end

    def self.purpose_label(purpose)
      PURPOSE_LABELS.fetch(purpose.to_s) do
        purpose.to_s.humanize
      end
    end
  end
end
