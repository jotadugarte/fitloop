# frozen_string_literal: true

require "csv"

module Admin
  class AnalyticsController < Admin::BaseController
    before_action :set_filters_and_events, only: [ :index, :export_csv ]

    def index
      # Calculate funnel metrics with a single GROUP BY query (avoids N+1).
      # Use reorder(nil) to drop the inherited ORDER BY which conflicts with GROUP BY in Postgres.
      counts_by_type = @events.reorder(nil)
                               .where(event_type: Analytics::FunnelStages::ORDERED)
                               .group(:event_type).count
      @funnel_counts = Analytics::FunnelStages::ORDERED.index_with { |stage| counts_by_type[stage] || 0 }

      # Conversion calculation
      paywall_count = @funnel_counts["paywall_viewed"] || 0
      succeeded_count = @funnel_counts["payment_succeeded"] || 0
      @conversion_percent = paywall_count > 0 ? (succeeded_count.to_f / paywall_count * 100).round(1) : 0.0
      @conversion_alert = @conversion_percent < Analytics::Thresholds.funnel_conversion_min_percent

      # Load payments using Admin::ReportingScope within date range
      payments = Admin::ReportingScope.call.where(paid_at: @start_date.beginning_of_day..@end_date.end_of_day)
      payments = payments.where(payment_method: @payment_method) if @payment_method.present?
      payments = payments.where(currency: @currency) if @currency.present?

      @single_payments_count = payments.succeeded.single_download.count
      @plan_payments_count = payments.succeeded.plan_subscription.count

      # Plans by tier (tier_months: 1, 2, 4)
      plans_by_tier = payments.succeeded.joins(:subscription).group("subscriptions.tier_months").count
      @plans_1_month = plans_by_tier[1] || 0
      @plans_2_month = plans_by_tier[2] || 0
      @plans_4_month = plans_by_tier[4] || 0

      # Exhausted monthly usages
      @exhausted_quotas_count = PlanMonthlyUsage.where(created_at: @start_date.beginning_of_day..@end_date.end_of_day)
                                                .where("downloads_used >= quota_limit")
                                                .count

      # Bot heuristic: low priority events in the last hour
      low_priority_count = UserEvent.where(priority: "low").where("occurred_at >= ?", 1.hour.ago).count
      @bot_heuristic = low_priority_count > Analytics::Thresholds.low_priority_events_per_hour

      # For select options
      @available_locales = UserEvent.where.not(locale: nil).distinct.pluck(:locale)
      @available_payment_methods = UserEvent.where("properties ->> 'payment_method' IS NOT NULL").distinct.pluck(Arel.sql("properties ->> 'payment_method'"))
      @available_currencies = UserEvent.where("properties ->> 'currency' IS NOT NULL").distinct.pluck(Arel.sql("properties ->> 'currency'"))
    end

    def export_csv
      csv_data = CSV.generate(headers: true) do |csv|
        csv << [
          "ID",
          "Event Type",
          "Priority",
          "Occurred At",
          "User ID",
          "Anonymous Session Key",
          "Tab ID",
          "Project ID",
          "Nesting Run ID",
          "IP",
          "User Agent",
          "Country Code",
          "Locale",
          "Properties"
        ]

        @events.find_each do |event|
          csv << [
            event.id,
            event.event_type,
            event.priority,
            event.occurred_at.iso8601,
            event.user_id,
            event.anonymous_session_key,
            event.tab_id,
            event.project_id,
            event.nesting_run_id,
            event.ip,
            event.user_agent,
            event.country_code,
            event.locale,
            event.properties.to_json
          ]
        end
      end

      send_data csv_data,
                filename: "user_events_export_#{Date.current}.csv",
                type: "text/csv; charset=utf-8",
                disposition: "attachment"
    end

    private

    def set_filters_and_events
      @start_date = begin
        Date.parse(params[:start_date])
      rescue ArgumentError, TypeError
        30.days.ago.to_date
      end if params[:start_date].present?
      @start_date ||= 30.days.ago.to_date

      @end_date = begin
        Date.parse(params[:end_date])
      rescue ArgumentError, TypeError
        Date.current
      end if params[:end_date].present?
      @end_date ||= Date.current

      @locale = params[:locale]
      @payment_method = params[:payment_method]
      @currency = params[:currency]

      @events = UserEvent.where(occurred_at: @start_date.beginning_of_day..@end_date.end_of_day).order(occurred_at: :desc)
      @events = @events.where(locale: @locale) if @locale.present?
      @events = @events.where("properties ->> 'payment_method' = ?", @payment_method) if @payment_method.present?
      @events = @events.where("properties ->> 'currency' = ?", @currency) if @currency.present?
    end
  end
end
