# frozen_string_literal: true

module Admin
  # [REQ-FIT-ADMIN-001] Query filters for /admin/ventas (no params mutation).
  class VentasFilter
    CR_ZONE = "America/Costa_Rica"

    def initialize(params)
      @params = params
    end

    def start_date_value
      return default_start_date unless @params.key?(:start_date)

      @params[:start_date].presence
    end

    def end_date_value
      return default_end_date unless @params.key?(:end_date)

      @params[:end_date].presence
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

      start_time = Time.zone.parse(date_str).beginning_of_day
      scope.where("created_at >= ?", start_time)
    rescue ArgumentError
      scope
    end

    def apply_end_date(scope, date_str)
      return scope if date_str.blank?

      end_time = Time.zone.parse(date_str).end_of_day
      scope.where("created_at <= ?", end_time)
    rescue ArgumentError
      scope
    end

    def apply_payment_methods(scope)
      methods = Array(@params[:payment_method]).reject(&:blank?)
      return scope if methods.empty?

      scope.where(payment_method: methods)
    end

    def apply_search(scope)
      term = @params[:search].to_s.strip
      return scope if term.blank?

      q = "%#{term}%"
      scope.where(
        "purchaser_name ILIKE :q OR purchaser_email ILIKE :q OR purchase_reference ILIKE :q OR sinpe_transfer_identification ILIKE :q",
        q: q
      )
    end
  end
end
