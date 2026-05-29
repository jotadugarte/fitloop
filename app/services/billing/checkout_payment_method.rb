# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Simulated checkout payment methods (aligned with Payment enums).
  module CheckoutPaymentMethod
    CARD_USD = Payment.payment_methods[:card_usd]
    CARD_CRC = Payment.payment_methods[:card_crc]
    SINPE_CRC = Payment.payment_methods[:sinpe_crc]
    ALL = Payment.payment_methods.values.freeze

    CONFIG = {
      CARD_USD => { payment_method: CARD_USD, currency: :usd, card: true },
      CARD_CRC => { payment_method: CARD_CRC, currency: :crc, card: true },
      SINPE_CRC => { payment_method: SINPE_CRC, currency: :crc, card: false }
    }.freeze

    class << self
      def config_for(method)
        CONFIG.fetch(method.to_s) { raise ArgumentError, "unknown payment_method" }
      end

      def currency_for(method)
        config_for(method).fetch(:currency)
      end

      def card?(method)
        config_for(method).fetch(:card)
      end

      def sinpe?(method)
        method.to_s == SINPE_CRC
      end

      def billing_method_for(method)
        card?(method) ? :card : :sinpe
      end
    end
  end
end
