# frozen_string_literal: true

# [REQ-FIT-BILL-001] Simulated checkout (single download or plan).
class CheckoutController < ApplicationController
  include RequiresBillingConfirmation
  include ResolvesWorkspaceTab
  include SetsWorkspaceProject

  before_action :set_workspace_project, only: %i[show simulate]
  before_action :load_checkout_context, only: %i[show simulate]
  before_action :reject_checkout_when_plan_quota_available!, only: %i[show simulate], if: :single_download_checkout?

  def show
    @billing_selection = billing_selection
    @available_payment_methods = billing_selection.fetch(:available_payment_methods)
    @simulate_outcome = resolve_simulate_outcome
    @selected_payment_method = resolve_selected_payment_method(selection: billing_selection)
    @sinpe_savings_amount = sinpe_savings_amount_preview
    @checkout_breakdown = checkout_breakdown_preview
    @plan_quota_exhausted =
      Billing::PlanDownloadAvailability.plan_quota_exhausted?(user: current_user)
    render :show
  end

  def simulate
    billing_context = {
      currency: billing_selection.fetch(:currency),
      iva_applicable: billing_selection.fetch(:iva_applicable)
    }

    if plan_checkout?
      result = Billing::SimulatePlanPurchase.call(
        user: current_user,
        tier_months: @tier_months,
        payment_method: params[:payment_method],
        outcome: params[:outcome],
        project: @project
      )
      if result == :failed
        redirect_to checkout_path, alert: t("billing.checkout.failure")
        return
      end

      redirect_after_plan_purchase!(result)
      return
    end

    result = Billing::SimulateSingleDownload.call(
      user: current_user,
      nesting_run: @nesting_run,
      payment_method: params[:payment_method],
      outcome: params[:outcome],
      iva_applicable: billing_context.fetch(:iva_applicable)
    )
    if result == :failed
      redirect_to checkout_path(nesting_run_id: @nesting_run.id), alert: t("billing.checkout.failure")
      return
    end

    redirect_to mis_pagos_path(auto_download: result[:grant].id),
                notice: t("billing.checkout.success_retention")
  end

  private

  def plan_checkout?
    @checkout_kind == :plan
  end

  def single_download_checkout?
    @checkout_kind == :single_download
  end

  def load_checkout_context
    if params[:nesting_run_id].present?
      @checkout_kind = :single_download
      @nesting_run = NestingRun.find_by(id: params[:nesting_run_id])
      return redirect_to(download_paywall_workshop_path, alert: t("workspace.expired")) unless @nesting_run
    else
      @cart = current_cart
      return redirect_to(download_paywall_workshop_path) unless @cart

      if @cart.tier_months.present?
        @checkout_kind = :plan
        @tier_months = @cart.tier_months
      else
        @checkout_kind = :single_download
        @nesting_run = @cart.nesting_run
        return redirect_to(download_paywall_workshop_path) unless @nesting_run
      end
    end

    @project ||= @nesting_run&.project
    return if @project.nil? || Workspace.bound_to_project?(session, @project)

    redirect_to start_project_path, alert: t("workspace.expired")
  end

  def current_cart
    Cart.find_by(user_id: current_user.id) if user_signed_in?
  end

  def reject_checkout_when_plan_quota_available!
    return if Billing::PlanDownloadAvailability.single_download_checkout_allowed?(user: current_user)

    redirect_to project_path(@project), notice: t("billing.checkout.plan_quota_prioritized")
  end

  def checkout_breakdown_preview
    billing_context = billing_context_for_checkout

    if plan_checkout?
      return Billing::CheckoutBreakdown.for_plan(tier_months: @tier_months, billing_context: billing_context)
    end

    if @cart && params[:nesting_run_id].blank?
      return Billing::CheckoutBreakdown.for_cart(cart: @cart, billing_context: billing_context)
    end

    Billing::CheckoutBreakdown.for_single_download(billing_context: billing_context, overage: false)
  end

  def billing_context_for_checkout
    payment_method = resolve_breakdown_payment_method(selection: billing_selection)
    {
      currency: billing_selection.fetch(:currency),
      payment_method: payment_method,
      iva_applicable: billing_selection.fetch(:iva_applicable)
    }
  end

  def billing_selection
    @billing_selection ||= Billing::PaymentSelection.resolve(request: request, session: session, user: current_user)
  end

  def resolve_selected_payment_method(selection:)
    requested = params[:payment_method].to_s.strip
    return normalize_payment_method(selection: selection) if requested.empty?

    if requested.start_with?("sinpe")
      return normalize_payment_method(selection: selection) unless @available_payment_methods.include?(:sinpe)
      return "sinpe_crc"
    end

    if requested.start_with?("card")
      return normalize_payment_method(selection: selection) unless @available_payment_methods.include?(:card)
      return selection.fetch(:currency) == :usd ? "card_usd" : "card_crc"
    end

    requested
  end

  def normalize_payment_method(selection:)
    method = selection.fetch(:payment_method)
    currency = selection.fetch(:currency)

    return "sinpe_crc" if method == :sinpe
    return "card_usd" if currency == :usd

    "card_crc"
  end

  def resolve_breakdown_payment_method(selection:)
    selected = resolve_selected_payment_method(selection: selection).to_s
    selected.start_with?("sinpe") ? :sinpe : :card
  end

  def resolve_simulate_outcome
    value = params[:outcome].to_s.strip
    return "success" if value.empty?

    %w[success failure].include?(value) ? value : "success"
  end

  def sinpe_savings_amount_preview
    return nil unless billing_selection.fetch(:currency) == :crc
    return nil unless @available_payment_methods.include?(:sinpe)

    billing_context = {
      currency: :crc,
      payment_method: :sinpe,
      iva_applicable: billing_selection.fetch(:iva_applicable)
    }

    breakdown = if plan_checkout?
                  Billing::CheckoutBreakdown.for_plan(tier_months: @tier_months, billing_context: billing_context)
                elsif @cart && params[:nesting_run_id].blank?
                  Billing::CheckoutBreakdown.for_cart(cart: @cart, billing_context: billing_context)
                else
                  Billing::CheckoutBreakdown.for_single_download(billing_context: billing_context, overage: false)
                end

    discount = breakdown.fetch(:discount_amount).to_f
    discount.positive? ? discount : nil
  end

  def redirect_after_plan_purchase!(result)
    current_cart&.destroy!
    if @project && Workspace.bound_to_project?(session, @project)
      redirect_to workshop_path, notice: t("billing.planes.success")
      return
    end

    redirect_to mis_pagos_path, notice: t("billing.planes.success")
  end
end
