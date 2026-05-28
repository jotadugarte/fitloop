# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Simulated single-download checkout (D37).
  class SimulateSingleDownload
    METHODS = {
      "card_usd" => { payment_method: "card_usd", currency: :usd, card: true },
      "card_crc" => { payment_method: "card_crc", currency: :crc, card: true },
      "sinpe_crc" => { payment_method: "sinpe_crc", currency: :crc, card: false }
    }.freeze

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
      raise ArgumentError, "unknown payment_method" unless METHODS.key?(@payment_method)
      raise ArgumentError, "nested_dxf missing" unless @nesting_run.project.nested_dxf.attached?
      return record_failure! if @outcome == "failure"

      record_success!
    end

    private

    def config
      METHODS.fetch(@payment_method)
    end

    def unit_amount
      overage = plan_quota_exhausted?
      Pricing.price(
        product: :single_download,
        currency: config.fetch(:currency),
        payment_method: config.fetch(:card) ? :card : :sinpe,
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
        payment_method: config.fetch(:card) ? :card : :sinpe,
        iva_applicable: @iva_applicable
      }
    end

    def record_failure!
      snapshot = snapshot_fields
      Payment.create!(
        user: @user,
        nesting_run: @nesting_run,
        status: "failed",
        payment_method: config[:payment_method],
        currency: config[:currency].to_s,
        amount: unit_amount,
        purpose: "single_download",
        **snapshot
      )
      :failed
    end

    def record_success!
      existing = DownloadGrant.find_by(user_id: @user.id, nesting_run_id: @nesting_run.id)
      if existing&.single_purchase? && existing.retention_active?
        payment = @user.payments.succeeded.where(nesting_run_id: @nesting_run.id, purpose: :single_download)
                         .order(created_at: :desc).first
        return { payment: payment, grant: existing, project: @nesting_run.project }
      end

      paid_at = Time.current
      result = nil
      ActiveRecord::Base.transaction do
        snapshot = snapshot_fields
        payment = Payment.create!(
          user: @user,
          nesting_run: @nesting_run,
          status: "succeeded",
          payment_method: config[:payment_method],
          currency: config[:currency].to_s,
          amount: unit_amount,
          purpose: "single_download",
          paid_at: paid_at,
          **snapshot
        )
        grant = DownloadGrant.create!(
          user: @user,
          nesting_run: @nesting_run,
          kind: "single_purchase",
          retained_until: paid_at + RetainNestedDxf::RETENTION_HOURS.hours
        )
        RetainNestedDxf.call(grant: grant, nesting_run: @nesting_run, paid_at: paid_at)
        result = { payment: payment, grant: grant, project: @nesting_run.project }
      end
      result
    end

    def snapshot_fields
      breakdown = CheckoutBreakdown.for_single_download(
        billing_context: billing_context,
        overage: plan_quota_exhausted?
      )
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
  end
end
