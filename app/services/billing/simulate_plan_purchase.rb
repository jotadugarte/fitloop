# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Simulated plan subscription checkout (D28, D29, D37).
  class SimulatePlanPurchase
    def self.call(user:, tier_months:, payment_method:, outcome:, project:, request: nil, session: nil)
      new(user: user, tier_months: tier_months, payment_method: payment_method, outcome: outcome, project: project, request: request, session: session).call
    end

    def initialize(user:, tier_months:, payment_method:, outcome:, project:, request: nil, session: nil)
      @user = user
      @tier_months = TierMonths.parse(tier_months)
      @payment_method = PaymentMethod.parse(payment_method)
      @outcome = outcome
      @project = project
      @request = request
      @session = session
    end

    def call
      raise ArgumentError, "user suspended" unless @user.operationally_active?
      return record_failure! if @outcome == "failure"

      record_success!
    end

    private

    def record_failure!
      payment = Payment.create!(
        base_payment_attrs(status: "pending", paid_at: nil).merge(snapshot_fields)
      )
      FailPayment.call(payment: payment, request: @request, session: @session)
      :failed
    end

    def record_success!
      payment = Payment.create!(
        base_payment_attrs(status: "pending", paid_at: nil).merge(snapshot_fields)
      )
      FulfillPayment.call(payment: payment, request: @request, session: @session)
      payment.reload
      { subscription: payment.subscription, payment: payment, project: @project }
    end

    def base_payment_attrs(status:, paid_at:, subscription: nil)
      {
        user: @user,
        subscription: subscription,
        status: status,
        payment_method: @payment_method.to_s,
        currency: @payment_method.currency.to_s,
        amount: plan_amount,
        purpose: "plan_subscription",
        paid_at: paid_at
      }
    end

    def plan_amount
      breakdown = plan_breakdown
      @payment_method.sinpe? ? breakdown.fetch(:subtotal) : breakdown.fetch(:list_price)
    end

    def plan_breakdown
      if (cart = cart_for_plan)
        CheckoutBreakdown.for_cart(cart: cart, billing_context: billing_context_for_snapshot)
      else
        CheckoutBreakdown.for_plan(tier_months: @tier_months, billing_context: billing_context_for_snapshot)
      end
    end

    def cart_for_plan
      cart = Cart.find_by(user_id: @user.id)
      return nil unless cart&.plan?
      return nil unless cart.tier_months.to_i == @tier_months.to_i
      return nil unless cart_currency_matches?(cart)

      cart
    end

    def cart_currency_matches?(cart)
      cart.currency_mode == @payment_method.currency.to_s
    end

    def billing_context_for_snapshot
      currency = @payment_method.currency
      {
        currency: currency.to_sym,
        payment_method: @payment_method.billing_method.to_sym,
        iva_applicable: currency.crc?
      }
    end

    def snapshot_fields
      breakdown = plan_breakdown
      {
        purchaser_name: @user.name.to_s,
        purchaser_email: @user.email.to_s,
        product_description: "plan_#{@tier_months.to_i}_months",
        list_price: breakdown.fetch(:list_price).to_f,
        discount_amount: breakdown.fetch(:discount_amount).to_f,
        subtotal: breakdown.fetch(:subtotal).to_f,
        tax_amount: breakdown.fetch(:tax_amount).to_f,
        total_amount: breakdown.fetch(:total_amount).to_f
      }
    end
  end
end
