# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Simulated single-download checkout (D37).
  class SimulateSingleDownload
    def self.call(user:, nesting_run:, payment_method:, outcome:, iva_applicable:)
      new(
        user: user,
        nesting_run: nesting_run,
        payment_method: payment_method,
        outcome: outcome,
        iva_applicable: iva_applicable
      ).call
    end

    def initialize(user:, nesting_run:, payment_method:, outcome:, iva_applicable:)
      @user = user
      @nesting_run = nesting_run
      @payment_method = payment_method
      @outcome = outcome
      @iva_applicable = iva_applicable
    end

    def call
      raise ArgumentError, "user suspended" unless @user.operationally_active?
      unless PlanDownloadAvailability.single_download_checkout_allowed?(user: @user)
        raise ArgumentError, "active plan monthly quota must be used before single purchase"
      end
      raise ArgumentError, "unknown payment_method" unless CheckoutPaymentMethod::ALL.include?(@payment_method)
      raise ArgumentError, "nested_dxf missing" unless @nesting_run.project.nested_dxf.attached?
      return record_failure! if @outcome == "failure"

      record_success!
    end

    private

    def config
      CheckoutPaymentMethod.config_for(@payment_method)
    end

    def unit_amount
      if (cart = cart_for_run)
        currency = config.fetch(:currency)
        cents = config.fetch(:card) ? cart.list_price_cents : cart.sinpe_price_cents
        return cents_to_amount(cents, currency)
      end

      overage = plan_quota_exhausted?
      Pricing.price(
        product: :single_download,
        currency: config.fetch(:currency),
        payment_method: CheckoutPaymentMethod.billing_method_for(@payment_method),
        overage: overage
      )
    end

    def plan_quota_exhausted?
      subscription = Subscription.active_at.find_by(user_id: @user.id)
      return false unless subscription

      QuotaCounter.for(subscription).exhausted?
    end

    def billing_context
      {
        currency: config.fetch(:currency),
        payment_method: CheckoutPaymentMethod.billing_method_for(@payment_method),
        iva_applicable: @iva_applicable
      }
    end

    def record_failure!
      payment = Payment.create!(
        user: @user,
        nesting_run: @nesting_run,
        status: "pending",
        payment_method: config[:payment_method],
        currency: config[:currency].to_s,
        amount: unit_amount,
        purpose: "single_download",
        **snapshot_fields
      )
      FailPayment.call(payment: payment)
      :failed
    end

    def record_success!
      existing = DownloadGrant.find_by(user_id: @user.id, nesting_run_id: @nesting_run.id)
      if existing&.single_purchase? && existing.retention_active?
        payment = @user.payments.succeeded.where(nesting_run_id: @nesting_run.id, purpose: :single_download)
                         .order(created_at: :desc).first
        return { payment: payment, grant: existing, project: @nesting_run.project }
      end

      payment = Payment.create!(
        user: @user,
        nesting_run: @nesting_run,
        status: "pending",
        payment_method: config[:payment_method],
        currency: config[:currency].to_s,
        amount: unit_amount,
        purpose: "single_download",
        **snapshot_fields
      )
      FulfillPayment.call(payment: payment)
      grant = DownloadGrant.find_by!(user_id: @user.id, nesting_run_id: @nesting_run.id)
      { payment: payment.reload, grant: grant, project: @nesting_run.project }
    end

    def snapshot_fields
      breakdown =
        if (cart = cart_for_run)
          CheckoutBreakdown.for_cart(cart: cart, billing_context: billing_context)
        else
          CheckoutBreakdown.for_single_download(
            billing_context: billing_context,
            overage: plan_quota_exhausted?
          )
        end
      {
        purchaser_name: @user.name.to_s,
        purchaser_email: @user.email.to_s,
        product_description: "single_download",
        list_price: breakdown.fetch(:list_price).to_f,
        discount_amount: breakdown.fetch(:discount_amount).to_f,
        subtotal: breakdown.fetch(:subtotal).to_f,
        tax_amount: breakdown.fetch(:tax_amount).to_f,
        total_amount: breakdown.fetch(:total_amount).to_f
      }
    end

    def cart_for_run
      cart = Cart.find_by(user_id: @user.id, nesting_run_id: @nesting_run.id)
      return nil unless cart
      return nil unless cart_currency_matches?(cart)

      cart
    end

    def cart_currency_matches?(cart)
      cart.currency_mode == config.fetch(:currency).to_s
    end

    def cents_to_amount(cents, currency)
      currency == :crc ? cents.to_i : (cents / 100.0)
    end
  end
end
