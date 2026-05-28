# frozen_string_literal: true

# [REQ-FIT-BILL-001] Internal single-item line; no cart page in UX (paywall → checkout).
class CartController < ApplicationController
  include SetsWorkspaceProject

  before_action :set_workspace_project, only: :create

  def show
    cart = current_cart
    return redirect_to(download_paywall_workshop_path) if cart.nil?

    redirect_to checkout_path
  end

  def create
    currency_mode = Billing::PaymentSelection.resolve(
      request: request,
      session: session,
      user: current_user
    ).fetch(:currency).to_s

    guest_token = session[:cart_guest_token] ||= SecureRandom.uuid
    Billing::CartUpsert.call(
      user: current_user,
      guest_token: guest_token,
      kind: params.fetch(:kind),
      nesting_run_id: params[:nesting_run_id],
      tier_months: params[:tier_months],
      currency_mode: currency_mode
    )
    session[:cart_guest_token] = guest_token unless current_user

    redirect_to checkout_path
  end

  def destroy
    current_cart&.destroy!
    redirect_to download_paywall_workshop_path
  end

  private

  def current_cart
    if user_signed_in?
      Cart.find_by(user_id: current_user.id)
    elsif session[:cart_guest_token].present?
      Cart.find_by(guest_token: session[:cart_guest_token])
    end
  end
end
