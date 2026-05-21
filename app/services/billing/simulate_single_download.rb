# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Simulated single-download checkout (D37).
  class SimulateSingleDownload
    METHODS = {
      "card_usd" => { payment_method: "card_usd", currency: "usd", amount: -> { Pricing.single_download_usd } },
      "sinpe_crc" => { payment_method: "sinpe_crc", currency: "crc", amount: -> { Pricing.single_download_sinpe_crc } }
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
      raise ArgumentError, "unknown payment_method" unless METHODS.key?(@payment_method)
      raise ArgumentError, "nested_dxf missing" unless @nesting_run.project.nested_dxf.attached?
      return record_failure! if @outcome == "failure"

      record_success!
    end

    private

    def config
      METHODS.fetch(@payment_method)
    end

    def record_failure!
      Payment.create!(
        user: @user,
        nesting_run: @nesting_run,
        status: "failed",
        payment_method: config[:payment_method],
        currency: config[:currency],
        amount: config[:amount].call,
        purpose: "single_download"
      )
      :failed
    end

    def record_success!
      paid_at = Time.current
      payment = Payment.create!(
        user: @user,
        nesting_run: @nesting_run,
        status: "succeeded",
        payment_method: config[:payment_method],
        currency: config[:currency],
        amount: config[:amount].call,
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
      { payment: payment, grant: grant, project: @nesting_run.project }
    end
  end
end
