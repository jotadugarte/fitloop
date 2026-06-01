# frozen_string_literal: true

module Admin
  # [REQ-FIT-ADMIN-001] Query filters for /admin/ventas (no params mutation).
  class VentasFilter
    CR_ZONE = "America/Costa_Rica"
    DATE_COLUMNS = {
      created_at: "created_at",
      paid_at: "paid_at"
    }.freeze

    def initialize(params = {}, date_column: :created_at)
      @params = params
      @date_column = date_column.to_sym
      raise ArgumentError, "invalid date_column: #{date_column}" unless DATE_COLUMNS.key?(@date_column)
    end

    def start_date_value
      return default_start_date unless @params.key?(:start_date)

      @params[:start_date].presence
    end

    def end_date_value
      return default_end_date unless @params.key?(:end_date)

      @params[:end_date].presence
    end

    def period_start_date
      start_date_value.presence || default_start_date
    end

    def period_end_date
      end_date_value.presence || default_end_date
    end

    def apply(scope)
      scope = apply_date_range(scope)
      scope = apply_payment_methods(scope)
      apply_search(scope)
    end

    def apply_status(scope)
      statuses = Array(@params[:status]).reject(&:blank?)
      return scope if statuses.empty?

      scope.where(status: statuses)
    end

    private

    def default_start_date
      Time.find_zone(CR_ZONE).now.beginning_of_month.to_date.to_s
    end

    def default_end_date
      Time.find_zone(CR_ZONE).now.end_of_month.to_date.to_s
    end

    def apply_date_range(scope)
      scope = apply_start_date(scope, start_date_value)
      apply_end_date(scope, end_date_value)
    end

    def apply_start_date(scope, date_str)
      return scope if date_str.blank?

      start_time = cr_zone.parse(date_str).beginning_of_day
      scope = exclude_null_date_column(scope) if @date_column == :paid_at
      scope.where("#{date_sql_column} >= ?", start_time)
    rescue ArgumentError
      scope
    end

    def apply_end_date(scope, date_str)
      return scope if date_str.blank?

      end_time = cr_zone.parse(date_str).end_of_day
      scope = exclude_null_date_column(scope) if @date_column == :paid_at
      scope.where("#{date_sql_column} <= ?", end_time)
    rescue ArgumentError
      scope
    end

    def exclude_null_date_column(scope)
      scope.where.not(date_sql_column => nil)
    end

    def date_sql_column
      DATE_COLUMNS.fetch(@date_column)
    end

    def apply_payment_methods(scope)
      methods = Array(@params[:payment_method]).reject(&:blank?)
      return scope if methods.empty?

      scope.where(payment_method: methods)
    end

    def apply_search(scope)
      term = @params[:search].to_s.strip
      return scope if term.blank?

      q = Admin::IlikeSearch.pattern(term)
      scope.where(
        "purchaser_name ILIKE :q ESCAPE '\\' OR purchaser_email ILIKE :q ESCAPE '\\' OR " \
        "purchase_reference ILIKE :q ESCAPE '\\' OR sinpe_transfer_identification ILIKE :q ESCAPE '\\'",
        q: q
      )
    end

    def cr_zone
      Time.find_zone(CR_ZONE)
    end
  end
end
