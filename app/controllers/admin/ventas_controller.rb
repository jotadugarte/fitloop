# frozen_string_literal: true

module Admin
  class VentasController < Admin::BaseController
    def index
      @filter = VentasFilter.new(params)
      @start_date = @filter.start_date_value
      @end_date = @filter.end_date_value
      @direction = params[:direction] == "asc" ? "asc" : "desc"

      base_scope = @filter.apply(ReportingScope.call)
      @declaration_totals = DeclarationTotals.for_scope(base_scope)
      status_counts = base_scope.group(:status).count
      @succeeded_count = status_counts.fetch("succeeded", 0)
      @failed_count = status_counts.fetch("failed", 0)
      @pending_count = status_counts.fetch("pending", 0)

      payments_scope = @filter.apply_status(base_scope)
      crc_page = page_param(:crc_page)
      usd_page = page_param(:usd_page)

      @crc_listing = VentasListing.call(
        payments_scope.where(currency: "crc"),
        direction: @direction,
        page: crc_page
      )
      @usd_listing = VentasListing.call(
        payments_scope.where(currency: "usd"),
        direction: @direction,
        page: usd_page
      )
      # Modals render only for rows visible on the current CRC/USD pages (see "Ver" in each table).
      @payments = @crc_listing.payments + @usd_listing.payments
    end

    def export_xlsx
      direction = params[:direction] == "asc" ? "asc" : "desc"
      xlsx_data = ExportPaymentsXlsx.call(filtered_payments_scope, direction: direction)

      send_data xlsx_data,
                filename: "ventas-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.xlsx",
                type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                disposition: "attachment"
    end

    def export_form150
      filter = VentasFilter.new(params, date_column: :paid_at)
      scope = filter.apply_status(filter.apply(ReportingScope.call))
      direction = params[:direction] == "asc" ? "asc" : "desc"
      start_date = filter.period_start_date
      end_date = filter.period_end_date
      xlsx_data = ExportForm150Xlsx.call(
        scope,
        start_date: start_date,
        end_date: end_date,
        direction: direction
      )

      send_data xlsx_data,
                filename: form150_filename(start_date, end_date),
                type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                disposition: "attachment"
    end

    private

    def form150_filename(start_date, end_date)
      "formulario-150-#{start_date}-#{end_date}.xlsx"
    end

    def filtered_payments_scope
      filter = VentasFilter.new(params)
      filter.apply_status(filter.apply(ReportingScope.call))
    end

    def page_param(name)
      raw = params[name].presence || params[:page]
      [ raw.to_i, 1 ].max
    end
  end
end
