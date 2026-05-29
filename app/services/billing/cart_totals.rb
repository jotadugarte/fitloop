# frozen_string_literal: true

module Billing
  class CartTotals
    # [REQ-FIT-BILL-001]
    # Cart shows list subtotal; IVA line only when country is CR (preview at checkout rates).
    def self.for_cart(cart:, billing_context:)
      raise ArgumentError, "cart must respond to list_price_cents" unless cart.respond_to?(:list_price_cents)

      breakdown = CheckoutBreakdown.for_cart(cart: cart, billing_context: billing_context)
      {
        list_subtotal_cents: cart.list_price_cents.to_i,
        breakdown: breakdown
      }
    end
  end
end
