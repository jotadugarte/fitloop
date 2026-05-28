# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Simulated plan subscription checkout (D28, D29, D37).
  class SimulatePlanPurchase
    ALLOWED_TIERS = Subscription::ALLOWED_TIER_MONTHS.freeze
    ALLOWED_METHODS = %w[card_usd card_crc sinpe_crc].freeze

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
      Payment.create!(base_payment_attrs(status: "failed", paid_at: nil).merge(snapshot_fields))
      :failed
    end

    def record_success!
      paid_at = Time.current
      result = nil
      ActiveRecord::Base.transaction do
        subscription = upsert_subscription!(paid_at)
        payment = Payment.create!(
          base_payment_attrs(status: "succeeded", paid_at: paid_at, subscription: subscription).merge(snapshot_fields)
        )
        result = { subscription: subscription, payment: payment, project: @project }
      end
      result
    end

    def upsert_subscription!(paid_at)
      existing = Subscription.active_at(paid_at).find_by(user_id: @user.id)
      anchor = existing&.ends_at || paid_at
      ends_at = PlanPeriod.ends_at_for(starts_at: anchor, tier_months: @tier_months, time_zone: @user.time_zone)
      return existing.tap { |sub| sub.update!(ends_at: ends_at) } if existing

      Subscription.create!(
        user: @user,
        tier_months: @tier_months,
        starts_at: paid_at,
        ends_at: ends_at
      )
    end

    def base_payment_attrs(status:, paid_at:, subscription: nil)
      {
        user: @user,
        subscription: subscription,
        status: status,
        payment_method: @payment_method,
        currency: @payment_method == "card_usd" ? "usd" : "crc",
        amount: plan_amount,
        purpose: "plan_subscription",
        paid_at: paid_at
      }
    end

    def plan_amount
      breakdown = plan_breakdown
      @payment_method == "sinpe_crc" ? breakdown.fetch(:subtotal) : breakdown.fetch(:list_price)
    end

    def plan_breakdown
      CheckoutBreakdown.for_plan(tier_months: @tier_months, billing_context: billing_context_for_snapshot)
    end

    def billing_context_for_snapshot
      currency = @payment_method == "card_usd" ? :usd : :crc
      payment_method = @payment_method.start_with?("sinpe") ? :sinpe : :card
      {
        currency: currency,
        payment_method: payment_method,
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
