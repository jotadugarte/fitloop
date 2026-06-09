# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] [REQ-FIT-BILL-002] [REQ-FIT-BILL-003] Grant entitlements after confirmed payment.
  class FulfillPayment
    def self.call(payment:, request: nil, session: nil)
      new(payment: payment, request: request, session: session).call
    end

    def initialize(payment:, request: nil, session: nil)
      @payment = payment
      @request = request
      @session = session
    end

    def call
      raise ArgumentError, "payment required" if @payment.nil?

      already_fulfilled = false
      res = nil

      ActiveRecord::Base.transaction do
        @payment.lock!
        if @payment.succeeded?
          already_fulfilled = true
        else
          res = case @payment.purpose
          when "single_download"
                  fulfill_single_download!
          when "plan_subscription"
                  fulfill_plan_subscription!
          else
                  raise ArgumentError, "unsupported payment purpose: #{@payment.purpose}"
          end
        end
      end

      return :already_fulfilled if already_fulfilled

      Analytics::TrackEvent.call(
        "payment_succeeded",
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

    def fulfill_single_download!
      nesting_run = @payment.nesting_run
      raise ArgumentError, "nesting_run required" if nesting_run.nil?

      paid_at = Time.current
      ActiveRecord::Base.transaction do
        mark_succeeded!(paid_at)
        grant = DownloadGrant.find_or_initialize_by(
          user_id: @payment.user_id,
          nesting_run_id: nesting_run.id
        )
        grant.kind = :single_purchase
        grant.save!
        RetainNestedDxf.call(grant: grant, nesting_run: nesting_run, paid_at: paid_at)
      end
      :fulfilled
    end

    def fulfill_plan_subscription!
      paid_at = Time.current
      tier_months = tier_months_from_product_description
      ActiveRecord::Base.transaction do
        subscription = upsert_subscription!(paid_at:, tier_months:)
        mark_succeeded!(paid_at)
        @payment.update!(subscription: subscription)
      end
      :fulfilled
    end

    def mark_succeeded!(paid_at)
      attrs = {
        status: :succeeded,
        paid_at: paid_at,
        checkout_abandoned_at: nil
      }
      attrs[:gateway_status] = Payment::ONVO_GATEWAY_SUCCEEDED if @payment.onvo_gateway?
      @payment.update!(attrs)
    end

    def tier_months_from_product_description
      match = @payment.product_description.to_s.match(/\Aplan_(\d+)_months\z/)
      raise ArgumentError, "invalid plan product_description" unless match

      TierMonths.parse(match[1]).to_i
    end

    def upsert_subscription!(paid_at:, tier_months:)
      user = @payment.user
      existing = Subscription.active_at(paid_at).find_by(user_id: user.id)
      anchor = existing&.ends_at || paid_at
      ends_at = PlanPeriod.ends_at_for(starts_at: anchor, tier_months: tier_months, time_zone: user.time_zone)
      return existing.tap { |sub| sub.update!(ends_at: ends_at) } if existing

      Subscription.create!(
        user: user,
        tier_months: tier_months,
        starts_at: paid_at,
        ends_at: ends_at
      )
    end
  end
end
