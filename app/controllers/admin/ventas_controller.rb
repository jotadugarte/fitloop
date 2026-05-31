# frozen_string_literal: true

module Admin
  class VentasController < Admin::BaseController
    def index
      base_scope = build_filtered_scope
      @direction = params[:direction] == "asc" ? "asc" : "desc"
      @page = [ params[:page].to_i, 1 ].max

      @declaration_totals = DeclarationTotals.for_scope(base_scope)
      @succeeded_count = base_scope.where(status: "succeeded").count
      @failed_count = base_scope.where(status: "failed").count
      @pending_count = base_scope.where(status: "pending").count

      @payments_scope = apply_status_filter(base_scope)
      @crc_listing = VentasListing.call(
        @payments_scope.where(currency: "crc"),
        direction: @direction,
        page: @page
      )
      @usd_listing = VentasListing.call(
        @payments_scope.where(currency: "usd"),
        direction: @direction,
        page: @page
      )
      @payments = @crc_listing.payments + @usd_listing.payments
      @total_count = @crc_listing.total_count + @usd_listing.total_count
    end

    def export
      base_scope = apply_status_filter(build_filtered_scope)

      direction = params[:direction] == "asc" ? "asc" : "desc"
      payments = base_scope.order(created_at: direction.to_sym)
      csv_data = ExportPaymentsCsv.call(payments)

      send_data csv_data,
                filename: "ventas-export-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.csv",
                type: "text/csv"
    end

    def export_xlsx
      base_scope = apply_status_filter(build_filtered_scope)

      direction = params[:direction] == "asc" ? "asc" : "desc"
      xlsx_data = ExportPaymentsXlsx.call(base_scope, direction: direction)

      send_data xlsx_data,
                filename: "ventas-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.xlsx",
                type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                disposition: "attachment"
    end

    def export_summary
      base_scope = apply_status_filter(build_filtered_scope)

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

    def apply_status_filter(scope)
      statuses = Array(params[:status]).reject(&:blank?)
      return scope if statuses.empty?

      scope.where(status: statuses)
    end
  end
end
