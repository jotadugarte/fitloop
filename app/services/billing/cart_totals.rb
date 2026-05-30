# frozen_string_literal: true

module Billing
  class CartTotals
    # [REQ-FIT-BILL-001]
    # Cart shows list subtotal; IVA line only when country is CR (preview at checkout rates).
    def self.for_cart(cart:, billing_context:)
      raise ArgumentError, "cart must respond to list_price_cents" unless cart.respond_to?(:list_price_cents)

      ctx = billing_context.is_a?(CheckoutContext) ? billing_context : CheckoutContext.from_session(billing_context)
      breakdown = CheckoutBreakdown.for_cart(cart: cart, billing_context: ctx)
      {
        list_subtotal_cents: CentsAmount.parse(cart.list_price_cents, currency: cart.currency_mode).to_i,
        breakdown: breakdown
      }
    end
  end
end
