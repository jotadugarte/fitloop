# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Simulated single-download checkout (D37).
  class SimulateSingleDownload
    METHODS = {
      "card_usd" => { payment_method: "card_usd", currency: "usd", full: -> { Pricing.single_download_usd }, overage: -> { Pricing.single_download_overage_usd } },
      "sinpe_crc" => { payment_method: "sinpe_crc", currency: "crc", full: -> { Pricing.single_download_sinpe_crc }, overage: -> { Pricing.single_download_overage_sinpe_crc } }
    }.freeze

    def self.call(user:, nesting_run:, payment_method:, outcome:)
      new(user: user, nesting_run: nesting_run, payment_method: payment_method, outcome: outcome).call
    end

    def initialize(user:, nesting_run:, payment_method:, outcome:)
      @user = user
      @nesting_run = nesting_run
      @payment_method = payment_method
      @outcome = outcome
    end

    def call
      raise ArgumentError, "user suspended" unless @user.operationally_active?
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
      plan_quota_exhausted? ? config[:overage].call : config[:full].call
    end

    def plan_quota_exhausted?
      subscription = Subscription.active_at.find_by(user_id: @user.id)
      return false unless subscription

      QuotaCounter.for(subscription).exhausted?
    end

    def record_failure!
      Payment.create!(
        user: @user,
        nesting_run: @nesting_run,
        status: "failed",
        payment_method: config[:payment_method],
        currency: config[:currency],
        amount: unit_amount,
        purpose: "single_download"
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
        payment = Payment.create!(
          user: @user,
          nesting_run: @nesting_run,
          status: "succeeded",
          payment_method: config[:payment_method],
          currency: config[:currency],
          amount: unit_amount,
          purpose: "single_download",
          paid_at: paid_at
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
  end
end
