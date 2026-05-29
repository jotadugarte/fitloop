# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Simulated plan subscription checkout (D28, D29, D37).
  class SimulatePlanPurchase
    ALLOWED_TIERS = Subscription::ALLOWED_TIER_MONTHS.freeze
    ALLOWED_METHODS = CheckoutPaymentMethod::ALL.freeze

    def self.call(user:, tier_months:, payment_method:, outcome:, project:)
      new(user: user, tier_months: tier_months, payment_method: payment_method, outcome: outcome, project: project).call
    end

    def initialize(user:, tier_months:, payment_method:, outcome:, project:)
      @user = user
      @tier_months = tier_months.to_i
      @payment_method = payment_method
      @outcome = outcome
      @project = project
    end

    def call
      raise ArgumentError, "user suspended" unless @user.operationally_active?
      raise ArgumentError, "invalid tier or payment_method" unless valid_selection?
      return record_failure! if @outcome == "failure"

      record_success!
    end

    private

    def valid_selection?
      ALLOWED_TIERS.include?(@tier_months) && ALLOWED_METHODS.include?(@payment_method)
    end

    def record_failure!
      payment = Payment.create!(
        base_payment_attrs(status: "pending", paid_at: nil).merge(snapshot_fields)
      )
      FailPayment.call(payment: payment)
      :failed
    end

    def record_success!
      payment = Payment.create!(
        base_payment_attrs(status: "pending", paid_at: nil).merge(snapshot_fields)
      )
      FulfillPayment.call(payment: payment)
      payment.reload
      { subscription: payment.subscription, payment: payment, project: @project }
    end

    def base_payment_attrs(status:, paid_at:, subscription: nil)
      {
        user: @user,
        subscription: subscription,
        status: status,
        payment_method: @payment_method,
        currency: CheckoutPaymentMethod.currency_for(@payment_method).to_s,
        amount: plan_amount,
        purpose: "plan_subscription",
        paid_at: paid_at
      }
    end

    def plan_amount
      breakdown = plan_breakdown
      CheckoutPaymentMethod.sinpe?(@payment_method) ? breakdown.fetch(:subtotal) : breakdown.fetch(:list_price)
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
      return nil unless cart.tier_months.to_i == @tier_months
      return nil unless cart_currency_matches?(cart)

      cart
    end

    def cart_currency_matches?(cart)
      cart.currency_mode == CheckoutPaymentMethod.currency_for(@payment_method).to_s
    end

    def billing_context_for_snapshot
      currency = CheckoutPaymentMethod.currency_for(@payment_method)
      {
        currency: currency,
        payment_method: CheckoutPaymentMethod.billing_method_for(@payment_method),
        iva_applicable: currency == :crc
      }
    end

    def snapshot_fields
      breakdown = plan_breakdown
      {
        purchaser_name: @user.name.to_s,
        purchaser_email: @user.email.to_s,
        product_description: "plan_#{@tier_months}_months",
        list_price: breakdown.fetch(:list_price).to_f,
        discount_amount: breakdown.fetch(:discount_amount).to_f,
        subtotal: breakdown.fetch(:subtotal).to_f,
        tax_amount: breakdown.fetch(:tax_amount).to_f,
        total_amount: breakdown.fetch(:total_amount).to_f
      }
    end
  end
end
