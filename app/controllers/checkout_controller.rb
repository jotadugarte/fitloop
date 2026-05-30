# frozen_string_literal: true

# [REQ-FIT-BILL-001] Simulated checkout (single download or plan).
class CheckoutController < ApplicationController
  include BillingHelper
  include RequiresBillingConfirmation
  include ResolvesWorkspaceTab
  include SetsWorkspaceProject

  before_action :set_workspace_project, only: %i[show simulate pay processing]
  before_action :load_checkout_context, only: %i[show simulate pay]
  before_action :reject_checkout_when_plan_quota_available!, only: %i[show simulate pay], if: :single_download_checkout?
  before_action :require_onvo_gateway!, only: %i[
    pay confirm_sinpe confirm_card three_ds_return payment_canceled_notice payment_failed_notice
  ]

  def show
    @billing_selection = billing_selection
    @available_payment_methods = billing_selection.fetch(:available_payment_methods)
    @simulate_outcome = resolve_simulate_outcome
    @selected_payment_method = resolve_selected_payment_method(selection: billing_selection)
    @sinpe_savings_amount = sinpe_savings_amount_preview
    @checkout_breakdown = checkout_breakdown_preview
    @plan_quota_exhausted =
      Billing::PlanDownloadAvailability.plan_quota_exhausted?(user: current_user)
    @onvo_checkout = Billing::Gateway.onvo?
    @resume_sinpe_payment = load_resume_sinpe_payment
    render :show
  end

  def pay
    unless Billing::Gateway.onvo?
      head :not_found
      return
    end

    selection = billing_selection
    @available_payment_methods = selection.fetch(:available_payment_methods)
    payment_method = resolve_selected_payment_method(selection: selection)
    billing_context = {
      currency: selection.fetch(:currency),
      payment_method: resolve_breakdown_payment_method(selection: selection),
      iva_applicable: selection.fetch(:iva_applicable)
    }

    if duplicate_sinpe_checkout_blocked?
      return render json: {
        error: t("billing.checkout.pending_lock.duplicate_checkout_blocked"),
        redirect_url: mis_pagos_path
      }, status: :conflict
    end

    result = Billing::StartOnvoCheckout.call(
      user: current_user,
      payment_method: payment_method,
      billing_context: billing_context,
      nesting_run: @nesting_run,
      tier_months: plan_checkout? ? @tier_months : nil,
      cart: @cart
    )

    render json: {
      payment_id: result.fetch(:payment).id,
      onvo_payment_intent_id: result.fetch(:onvo_payment_intent_id),
      onvo_publishable_key: ENV.fetch("ONVO_PUBLISHABLE_KEY", nil)
    }
  rescue Billing::Onvo::ApiError => error
    render json: { error: error.user_message }, status: :unprocessable_entity
  end

  def confirm_sinpe
    payment = current_user.payments.find(params[:payment_id])
    sinpe = Billing::Onvo::SinpeInput.parse!(
      identification: params[:sinpe_identification],
      mobile_number: params[:sinpe_mobile_number]
    )
    result = Billing::Onvo::ConfirmSinpePayment.call(
      payment: payment,
      identification: sinpe.fetch(:identification),
      mobile_number: sinpe.fetch(:mobile_number)
    )

    render json: result.merge(
      amount_label: format_onvo_amount(result.fetch(:amount), result.fetch(:currency))
    )
  rescue ArgumentError => error
    render json: { error: onvo_validation_message(error.message) }, status: :unprocessable_entity
  rescue Billing::Onvo::ApiError => error
    render json: { error: onvo_api_error_message(error, context: :sinpe) }, status: :unprocessable_entity
  end

  def confirm_card
    payment = current_user.payments.find(params[:payment_id])
    card = Billing::Onvo::CardInput.parse!(
      holder_name: params[:card_holder_name],
      card_number: params[:card_number],
      card_exp: params[:card_exp],
      cvv: params[:card_cvv]
    )
    result = Billing::Onvo::ConfirmCardPayment.call(
      payment: payment,
      holder_name: card.fetch(:holder_name),
      card_number: card.fetch(:card_number),
      exp_month: card.fetch(:exp_month),
      exp_year: card.fetch(:exp_year),
      cvv: card.fetch(:cvv),
      return_url: checkout_return_url(host: request.base_url)
    )

    render_confirm_card_result!(payment, result)
  rescue ArgumentError => error
    render json: { error: onvo_validation_message(error.message) }, status: :unprocessable_entity
  rescue Billing::Onvo::ApiError => error
    render json: { error: error.user_message }, status: :unprocessable_entity
  end

  def processing
    @payment = current_user.payments.find(params[:payment_id])
    @status_url = checkout_payment_status_path(@payment)
    @processing_from_workshop = params[:context].to_s == "workshop"
    render :processing
  end

  def payment_status
    payment = current_user.payments.find(params[:payment_id])
    render json: Billing::PaymentStatusResponse.for(payment: payment, routes: self)
  end

  def release_pending_lock
    payment = current_user.payments.find(params[:payment_id])
    Billing::ReleasePendingCheckoutLock.call(payment: payment, user: current_user)
    redirect_to mis_pagos_path, notice: t("billing.checkout.pending_lock.released")
  end

  def three_ds_return
    intent_id = params[:payment_intent_id].to_s.strip
    raise ActiveRecord::RecordNotFound if intent_id.blank?

    payment = current_user.payments.find_by!(onvo_payment_intent_id: intent_id)
    intent = Billing::Onvo::ReconcilePaymentIntent.call(payment: payment)
    redirect_after_onvo_three_ds_return!(payment: payment, intent_status: intent.fetch(:status).to_s)
  end

  def payment_canceled_notice
    payment = current_user.payments.find(params[:payment_id])
    redirect_to checkout_path(checkout_redirect_params_for_payment(payment)),
                alert: t("billing.checkout.onvo.payment_canceled")
  end

  def payment_failed_notice
    payment = current_user.payments.find(params[:payment_id])
    Billing::FailPayment.call(payment: payment) unless payment.failed?
    redirect_to checkout_path(checkout_redirect_params_for_payment(payment)),
                alert: t("billing.checkout.onvo.payment_failed")
  end

  def simulate
    if Billing::Gateway.onvo?
      redirect_to checkout_path(checkout_redirect_params), alert: t("billing.checkout.onvo_use_pay")
      return
    end
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

  def duplicate_sinpe_checkout_blocked?
    return false unless single_download_checkout? && @nesting_run

    Payment.pending.single_download.sinpe_crc
           .where(user_id: current_user.id, nesting_run_id: @nesting_run.id, superseded_at: nil)
           .any?(&:checkout_lock_active?)
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

    if @cart && params[:nesting_run_id].blank?
      return Billing::CheckoutBreakdown.for_cart(cart: @cart, billing_context: billing_context)
    end

    if plan_checkout?
      return Billing::CheckoutBreakdown.for_plan(tier_months: @tier_months, billing_context: billing_context)
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

    breakdown = if @cart && params[:nesting_run_id].blank?
                  Billing::CheckoutBreakdown.for_cart(cart: @cart, billing_context: billing_context)
                elsif plan_checkout?
                  Billing::CheckoutBreakdown.for_plan(tier_months: @tier_months, billing_context: billing_context)
                else
                  Billing::CheckoutBreakdown.for_single_download(billing_context: billing_context, overage: false)
                end

    discount = breakdown.fetch(:discount_amount).to_f
    discount.positive? ? discount : nil
  end

  def require_onvo_gateway!
    head :not_found unless Billing::Gateway.onvo?
  end

  def render_confirm_card_result!(payment, result)
    status = result.fetch(:status).to_s
    if status == "failed"
      Billing::FailPayment.call(payment: payment)
      render json: { error: t("billing.checkout.onvo.payment_failed") }, status: :unprocessable_entity
      return
    end

    if status == "requires_payment_method"
      render json: { error: t("billing.checkout.onvo.payment_failed") }, status: :unprocessable_entity
      return
    end

    render json: result
  end

  def onvo_validation_message(key)
    I18n.t("billing.checkout.onvo.validation.#{key}", default: key.to_s.humanize)
  end

  alias onvo_card_validation_message onvo_validation_message

  def onvo_api_error_message(error, context: nil)
    return error.user_message if context.nil?

    Billing::Onvo::ApiError.new(error.message, status: error.status, body: error.body, context: context).user_message
  end

  def load_resume_sinpe_payment
    return nil if params[:payment_id].blank?

    payment = current_user.payments.find_by(id: params[:payment_id])
    return nil unless payment&.sinpe_crc? && payment.pending? && !payment.superseded?

    payment
  end

  def redirect_after_onvo_three_ds_return!(payment:, intent_status:)
    if %w[succeeded processing].include?(intent_status)
      redirect_to checkout_processing_path(payment)
      return
    end

    if intent_status == "failed"
      redirect_to checkout_payment_failed_path(payment)
      return
    end

    redirect_to checkout_payment_canceled_path(payment)
  end

  def checkout_redirect_params_for_payment(payment)
    params = {}
    params[:nesting_run_id] = payment.nesting_run_id if payment.nesting_run_id.present?
    params
  end

  def format_onvo_amount(amount, currency)
    return format_billing_crc(amount) if currency.to_s == "crc"

    format_billing_usd(amount)
  end

  def checkout_redirect_params
    params = {}
    params[:nesting_run_id] = @nesting_run.id if @nesting_run.present?
    params[:tier_months] = @tier_months if plan_checkout?
    params
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
