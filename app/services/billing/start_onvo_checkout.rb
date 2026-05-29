# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Start ONVO checkout: pending Payment + payment intent (no grant yet).
  class StartOnvoCheckout
    def self.call(user:, payment_method:, billing_context:, nesting_run: nil, tier_months: nil, cart: nil, client: nil)
      new(
        user: user,
        payment_method: payment_method,
        billing_context: billing_context,
        nesting_run: nesting_run,
        tier_months: tier_months,
        cart: cart,
        client: client
      ).call
    end

    def initialize(user:, payment_method:, billing_context:, nesting_run: nil, tier_months: nil, cart: nil, client: nil)
      @user = user
      @payment_method = payment_method
      @billing_context = billing_context
      @nesting_run = nesting_run
      @tier_months = tier_months
      @cart = cart
      @client = client
    end

    def call
      raise ArgumentError, "ONVO gateway not enabled" unless Gateway.onvo?

      breakdown = resolve_breakdown
      payment = create_pending_payment!(breakdown)
      intent = Onvo::CreatePaymentIntent.call(payment: payment, breakdown: breakdown, client: @client)

      {
        payment: payment,
        onvo_payment_intent_id: intent.fetch(:id)
      }
    end

    private

    def resolve_breakdown
      if @cart
        CheckoutBreakdown.for_cart(cart: @cart, billing_context: @billing_context)
      elsif @tier_months
        CheckoutBreakdown.for_plan(tier_months: @tier_months, billing_context: @billing_context)
      else
        CheckoutBreakdown.for_single_download(
          billing_context: @billing_context,
          overage: plan_quota_exhausted?
        )
      end
    end

    def plan_quota_exhausted?
      subscription = Subscription.active_at.find_by(user_id: @user.id)
      return false unless subscription

      QuotaCounter.for(subscription).exhausted?
    end

    def create_pending_payment!(breakdown)
      Payment.create!(
        user: @user,
        nesting_run: @nesting_run,
        status: :pending,
        payment_method: @payment_method,
        currency: breakdown.fetch(:currency).to_s,
        amount: breakdown.fetch(:total_amount),
        purpose: checkout_purpose,
        **snapshot_fields(breakdown)
      )
    end

    def checkout_purpose
      @tier_months ? "plan_subscription" : "single_download"
    end

    def snapshot_fields(breakdown)
      description = if @tier_months
                        "plan_#{@tier_months}_months"
                      else
                        "single_download"
                      end

      {
        purchaser_name: @user.name.to_s,
        purchaser_email: @user.email.to_s,
        product_description: description,
        list_price: breakdown.fetch(:list_price).to_f,
        discount_amount: breakdown.fetch(:discount_amount).to_f,
        subtotal: breakdown.fetch(:subtotal).to_f,
        tax_amount: breakdown.fetch(:tax_amount).to_f,
        total_amount: breakdown.fetch(:total_amount).to_f
      }
    end
  end
end
