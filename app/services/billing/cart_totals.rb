# frozen_string_literal: true

module Billing
  class CartTotals
    # [REQ-FIT-BILL-001]
    # Cart page shows list subtotal only (no IVA, no SINPE discount applied yet).
    #
    # Preconditions:
    # - cart responds to list_price_cents
    # Postconditions:
    # - returns Hash including :list_subtotal_cents (Integer)
    def self.for_cart(cart)
      raise ArgumentError, "cart must respond to list_price_cents" unless cart.respond_to?(:list_price_cents)

      list_subtotal_cents = cart.list_price_cents.to_i
      raise ArgumentError, "list_subtotal_cents must be positive" unless list_subtotal_cents.positive?

      { list_subtotal_cents: list_subtotal_cents }
    end
  end
end

