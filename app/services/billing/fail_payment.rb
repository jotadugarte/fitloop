# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Marks a payment failed from gateway confirmation.
  class FailPayment
    def self.call(payment:, failure_code: nil, failure_message: nil, request: nil, session: nil)
      new(payment: payment, failure_code: failure_code, failure_message: failure_message, request: request, session: session).call
    end

    def initialize(payment:, failure_code: nil, failure_message: nil, request: nil, session: nil)
      @payment = payment
      @failure_code = failure_code
      @failure_message = failure_message
      @request = request
      @session = session
    end

    def call
      return :already_terminal if @payment.failed?

      res = nil
      ActiveRecord::Base.transaction do
        @payment.update!(
          status: :failed,
          gateway_status: "failed",
          failure_code: @failure_code,
          failure_message: @failure_message
        )
        purge_staging_pre_retention!
        res = :failed
      end

      Analytics::TrackEvent.call(
        "payment_failed",
        user_id: @payment.user_id,
        anonymous_session_key: @session&.[](:anonymous_session_key),
        project_id: @payment.nesting_run&.project_id,
        nesting_run_id: @payment.nesting_run_id,
        ip: @request&.remote_ip,
        user_agent: @request&.user_agent,
        country_code: @request ? Analytics::ResolveCountry.call(@request) : nil,
        locale: @request ? I18n.locale.to_s : nil
      )

      res
    end

    private

    def purge_staging_pre_retention!
      return unless @payment.single_download? && @payment.nesting_run_id.present?

      grant = DownloadGrant.find_by(
        user_id: @payment.user_id,
        nesting_run_id: @payment.nesting_run_id
      )
      return if grant.nil?
      return if grant.retention_active?

      grant.purge_retained_blob!
    end
  end
end
