# frozen_string_literal: true

module Admin
  class VentasController < Admin::BaseController
    def index
      base_scope = build_filtered_scope
      @direction = params[:direction] == "asc" ? "asc" : "desc"

      # Compute metrics on the filtered base scope (excluding status filter)
      @total_revenue_crc = base_scope.where(status: "succeeded", currency: "crc").sum("COALESCE(NULLIF(total_amount, 0), amount)")
      @total_revenue_usd = base_scope.where(status: "succeeded", currency: "usd").sum("COALESCE(NULLIF(total_amount, 0), amount)")
      @succeeded_count = base_scope.where(status: "succeeded").count
      @failed_count = base_scope.where(status: "failed").count
      @pending_count = base_scope.where(status: "pending").count

      # Apply status filter for listing
      @payments_scope = base_scope
      statuses = Array(params[:status]).reject(&:blank?)
      if statuses.any?
        @payments_scope = @payments_scope.where(status: statuses)
      end

      # Pagination
      @page = [params[:page].to_i, 1].max
      per_page = 20
      @total_count = @payments_scope.count
      @total_pages = (@total_count.to_f / per_page).ceil
      @payments = @payments_scope.order(created_at: @direction.to_sym).limit(per_page).offset((@page - 1) * per_page)
    end

    def export
      base_scope = build_filtered_scope
      statuses = Array(params[:status]).reject(&:blank?)
      if statuses.any?
        base_scope = base_scope.where(status: statuses)
      end

      direction = params[:direction] == "asc" ? "asc" : "desc"
      payments = base_scope.order(created_at: direction.to_sym)
      csv_data = ExportPaymentsCsv.call(payments)

      send_data csv_data,
                filename: "ventas-export-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.csv",
                type: "text/csv"
    end

    def export_xlsx
      base_scope = build_filtered_scope
      statuses = Array(params[:status]).reject(&:blank?)
      if statuses.any?
        base_scope = base_scope.where(status: statuses)
      end

      direction = params[:direction] == "asc" ? "asc" : "desc"
      xlsx_data = ExportPaymentsXlsx.call(base_scope, direction: direction)

      send_data xlsx_data,
                filename: "ventas-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.xlsx",
                type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                disposition: "attachment"
    end

    def export_summary
      base_scope = build_filtered_scope
      statuses = Array(params[:status]).reject(&:blank?)
      if statuses.any?
        base_scope = base_scope.where(status: statuses)
      end

      direction = params[:direction] == "asc" ? "asc" : "desc"
      csv_data = ExportSummaryCsv.call(base_scope, direction: direction)

      send_data csv_data,
                filename: "ventas-resumen-declaracion-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.csv",
                type: "text/csv"
    end

    private

    def build_filtered_scope
      scope = Payment.all

      # Default dates to the first and last day of the current month in America/Costa_Rica
      cr_time = Time.find_zone("America/Costa_Rica").now
      params[:start_date] = cr_time.beginning_of_month.to_date.to_s if params[:start_date].nil?
      params[:end_date] = cr_time.end_of_month.to_date.to_s if params[:end_date].nil?

      # Apply date filters
      if params[:start_date].present?
        begin
          start_time = Time.zone.parse(params[:start_date]).beginning_of_day
          scope = scope.where("created_at >= ?", start_time)
        rescue ArgumentError
        end
      end

      if params[:end_date].present?
        begin
          end_time = Time.zone.parse(params[:end_date]).end_of_day
          scope = scope.where("created_at <= ?", end_time)
        rescue ArgumentError
        end
      end

      # Apply payment method filter (handles single value or array)
      methods = Array(params[:payment_method]).reject(&:blank?)
      if methods.any?
        scope = scope.where(payment_method: methods)
      end

      # Apply search
      if params[:search].present?
        q = "%#{params[:search]}%"
        scope = scope.where(
          "purchaser_name ILIKE :q OR purchaser_email ILIKE :q OR purchase_reference ILIKE :q OR sinpe_transfer_identification ILIKE :q",
          q: q
        )
      end

      scope
    end
  end
end
