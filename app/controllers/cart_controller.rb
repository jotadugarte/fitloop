class CartController < ApplicationController
  def show
  end

  def create
    cart = Cart.create!(
      kind: params.fetch(:kind),
      nesting_run_id: params.fetch(:nesting_run_id),
      currency_mode: params.fetch(:currency_mode),
      overage: false,
      guest_token: "guest-cart-placeholder",
      list_price_cents: 250,
      sinpe_price_cents: 200
    )

    redirect_to cart_path, notice: "Added to cart #{cart.id}"
  end

  def destroy
    Cart.order(id: :desc).first&.destroy!
    redirect_to cart_path, notice: "Cart cleared"
  end
end
