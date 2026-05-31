# frozen_string_literal: true

module Admin
  class AnalyticsController < Admin::BaseController
    def index
      # Retrieve filters
      @start_date = params[:start_date].present? ? Date.parse(params[:start_date]) : 30.days.ago.to_date
      @end_date = params[:end_date].present? ? Date.parse(params[:end_date]) : Date.current
      @locale = params[:locale]
      @payment_method = params[:payment_method]
      @currency = params[:currency]

      # Load events
      events = UserEvent.where(occurred_at: @start_date.beginning_of_day..@end_date.end_of_day)
      events = events.where(locale: @locale) if @locale.present?
      events = events.where("properties ->> 'payment_method' = ?", @payment_method) if @payment_method.present?
      events = events.where("properties ->> 'currency' = ?", @currency) if @currency.present?

      # Calculate funnel metrics
      @funnel_counts = {}
      Analytics::FunnelStages::ORDERED.each do |stage|
        @funnel_counts[stage] = events.where(event_type: stage).count
      end

      # Conversion calculation
      paywall_count = @funnel_counts["paywall_viewed"] || 0
      succeeded_count = @funnel_counts["payment_succeeded"] || 0
      @conversion_percent = paywall_count > 0 ? (succeeded_count.to_f / paywall_count * 100).round(1) : 0.0
      @conversion_alert = @conversion_percent < Analytics::Thresholds.funnel_conversion_min_percent

      # For select options
      @available_locales = UserEvent.where.not(locale: nil).distinct.pluck(:locale)
      @available_payment_methods = UserEvent.where("properties ->> 'payment_method' IS NOT NULL").distinct.pluck(Arel.sql("properties ->> 'payment_method'"))
      @available_currencies = UserEvent.where("properties ->> 'currency' IS NOT NULL").distinct.pluck(Arel.sql("properties ->> 'currency'"))
    end
  end
end
