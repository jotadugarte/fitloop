# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Simulated checkout payment methods (aligned with Payment enums).
  # Facade delegating to Billing::PaymentMethod value object.
  module CheckoutPaymentMethod
    CARD_USD = Payment.payment_methods[:card_usd]
    CARD_CRC = Payment.payment_methods[:card_crc]
    SINPE_CRC = Payment.payment_methods[:sinpe_crc]
    ALL = PaymentMethod::ALL.freeze

    class << self
      def config_for(method)
        vo = PaymentMethod.parse(method)
        {
          payment_method: vo.to_s,
          currency: vo.currency.to_sym,
          card: vo.card?
        }
      end

      def currency_for(method)
        PaymentMethod.parse(method).currency.to_sym
      end

      def card?(method)
        PaymentMethod.parse(method).card?
      end

      def sinpe?(method)
        PaymentMethod.parse(method).sinpe?
      end

      def billing_method_for(method)
        PaymentMethod.parse(method).billing_method.to_sym
      end
    end
  end
end
