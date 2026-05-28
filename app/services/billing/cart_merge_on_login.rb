# frozen_string_literal: true

module Billing
  class CartMergeOnLogin
    # [REQ-FIT-BILL-001]
    # Rule (D15): user cart wins. If a guest cart exists, discard it.
    #
    # Preconditions:
    # - user is a persisted User
    # - guest_token is a String or nil
    # Postconditions:
    # - if both guest and user carts existed, guest cart is destroyed
    def self.call(user:, guest_token:)
      raise ArgumentError, "user must be present" if user.nil?

      token = guest_token.is_a?(String) ? guest_token.strip : ""
      return if token.empty?

      user_cart = Cart.find_by(user_id: user.id)
      guest_cart = Cart.find_by(guest_token: token)

      return if guest_cart.nil?
      return if user_cart.nil? && guest_cart.user_id.present?

      if user_cart
        guest_cart.destroy!
      else
        guest_cart.update!(user_id: user.id, guest_token: nil)
      end
    end
  end
end

