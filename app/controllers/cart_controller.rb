class CartController < ApplicationController
  def show
  end

  def create
    if Cart.exists?
      render plain: "confirm replace", status: :unprocessable_content
      return
    end

    guest_token = SecureRandom.uuid
    cart = Cart.create!(
      kind: params.fetch(:kind),
      nesting_run_id: params.fetch(:nesting_run_id),
      currency_mode: params.fetch(:currency_mode),
      overage: false,
      guest_token: guest_token,
      list_price_cents: 250,
      sinpe_price_cents: 200
    )

    session[:cart_guest_token] = guest_token
    redirect_to cart_path, notice: "Added to cart #{cart.id}"
  end

  def destroy
    Cart.order(id: :desc).first&.destroy!
    redirect_to cart_path, notice: "Cart cleared"
  end
end
