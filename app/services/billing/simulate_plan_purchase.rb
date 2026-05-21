# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-002] Simulated plan subscription checkout (D28, D29, D37).
  class SimulatePlanPurchase
    ALLOWED_TIERS = Subscription::ALLOWED_TIER_MONTHS.freeze
    ALLOWED_METHODS = %w[card_usd sinpe_crc].freeze

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
      Payment.create!(base_payment_attrs(status: "failed", paid_at: nil))
      :failed
    end

    def record_success!
      paid_at = Time.current
      subscription = upsert_subscription!(paid_at)
      payment = Payment.create!(base_payment_attrs(status: "succeeded", paid_at: paid_at, subscription: subscription))
      { subscription: subscription, payment: payment, project: @project }
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
      Pricing.public_send(plan_pricing_method)
    end

    def plan_pricing_method
      months = @tier_months == 1 ? "1_month" : "#{@tier_months}_months"
      suffix = @payment_method == "card_usd" ? "card_usd" : "sinpe_crc"
      "plan_#{months}_#{suffix}"
    end
  end
end
