# frozen_string_literal: true

# [REQ-FIT-BILL-001] Internal single-item line; paywall posts here then redirects to checkout.
class CartController < ApplicationController
  include SetsWorkspaceProject

  before_action :set_workspace_project, only: :create
  before_action :load_pending_cart!, only: %i[replace update cancel_replace]

  helper_method :cart_line_summary

  def show
    cart = current_cart
    return redirect_to(download_paywall_workshop_path) if cart.nil?

    redirect_to checkout_path
  end

  def create
    existing = current_cart
    if existing && different_cart_line?(existing)
      stash_pending_cart!
      redirect_to cart_replace_path
      return
    end

    upsert_cart!
    redirect_to checkout_path
  end

  def replace
    return redirect_to(download_paywall_workshop_path) if @pending_cart.nil?

    @existing_cart = current_cart
  end

  def update
    return redirect_to(download_paywall_workshop_path) if @pending_cart.nil?

    upsert_cart_from_pending!
    session.delete(:pending_cart)
    redirect_to checkout_path
  rescue ArgumentError
    session.delete(:pending_cart)
    redirect_to download_paywall_workshop_path, alert: t("billing.cart.replace.invalid")
  end

  def cancel_replace
    session.delete(:pending_cart)
    redirect_to download_paywall_workshop_path
  end

  def destroy
    current_cart&.destroy!
    session.delete(:pending_cart)
    redirect_to download_paywall_workshop_path
  end

  def cart_line_summary(source)
    return t("billing.cart.replace.line_unknown") if source.blank?

    kind, tier = cart_line_kind_and_tier(source)
    if kind == Cart.kinds[:plan]
      t("billing.cart.replace.line_plan", months: tier.to_i)
    else
      t("billing.cart.replace.line_download")
    end
  end

  private

  def cart_line_kind_and_tier(source)
    case source
    when Cart
      [source.kind, source.tier_months]
    when Billing::PendingCart
      [source.kind, source.tier_months]
    else
      data = source.stringify_keys
      [data.fetch("kind").to_s, data["tier_months"]]
    end
  end

  def upsert_cart!
    guest_token = session[:cart_guest_token] ||= SecureRandom.uuid
    Billing::CartUpsert.call(
      user: current_user,
      guest_token: guest_token,
      kind: cart_kind_param,
      nesting_run_id: params[:nesting_run_id],
      tier_months: params[:tier_months],
      currency_mode: resolved_currency_mode
    )
    session[:cart_guest_token] = guest_token unless current_user
  end

  def upsert_cart_from_pending!
    guest_token = session[:cart_guest_token] ||= SecureRandom.uuid
    Billing::CartUpsert.call(
      user: current_user,
      guest_token: guest_token,
      kind: @pending_cart.kind,
      nesting_run_id: @pending_cart.nesting_run_id,
      tier_months: @pending_cart.tier_months,
      currency_mode: @pending_cart.currency_mode
    )
    session[:cart_guest_token] = guest_token unless current_user
  end

  def stash_pending_cart!
    session[:pending_cart] = Billing::PendingCart.new(
      "kind" => cart_kind_param,
      "nesting_run_id" => params[:nesting_run_id],
      "tier_months" => params[:tier_months],
      "currency_mode" => resolved_currency_mode
    ).to_h
  end

  def load_pending_cart!
    @pending_cart = Billing::PendingCart.from_session(session[:pending_cart])
  rescue ArgumentError
    session.delete(:pending_cart)
    @pending_cart = nil
  end

  def resolved_currency_mode
    Billing::PaymentSelection.resolve(
      request: request,
      session: session,
      user: current_user
    ).fetch(:currency).to_s
  end

  def cart_kind_param
    params.fetch(:kind)
  end

  def different_cart_line?(existing)
    kind = cart_kind_param
    return true unless existing.kind == kind

    if kind == Cart.kinds[:plan]
      existing.tier_months.to_i != params[:tier_months].to_i
    else
      existing.nesting_run_id.to_i != params[:nesting_run_id].to_i
    end
  end

  def current_cart
    if user_signed_in?
      Cart.find_by(user_id: current_user.id)
    elsif session[:cart_guest_token].present?
      Cart.find_by(guest_token: session[:cart_guest_token])
    end
  end
end
