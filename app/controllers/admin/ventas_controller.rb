# frozen_string_literal: true

module Admin
  class VentasController < Admin::BaseController
    def index
      filter = VentasFilter.new(params)
      @start_date = filter.start_date_value
      @end_date = filter.end_date_value
      @direction = params[:direction] == "asc" ? "asc" : "desc"

      base_scope = filter.apply(Payment.all)
      @declaration_totals = DeclarationTotals.for_scope(base_scope)
      @succeeded_count = base_scope.where(status: "succeeded").count
      @failed_count = base_scope.where(status: "failed").count
      @pending_count = base_scope.where(status: "pending").count

      payments_scope = filter.apply_status(base_scope)
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
      @total_count = @crc_listing.total_count + @usd_listing.total_count
    end

    def export
      send_filtered_csv(ExportPaymentsCsv)
    end

    def export_xlsx
      filter = VentasFilter.new(params)
      base_scope = filter.apply_status(filter.apply(Payment.all))
      direction = params[:direction] == "asc" ? "asc" : "desc"
      xlsx_data = ExportPaymentsXlsx.call(base_scope, direction: direction)

      send_data xlsx_data,
                filename: "ventas-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.xlsx",
                type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                disposition: "attachment"
    end

    def export_summary
      filter = VentasFilter.new(params)
      base_scope = filter.apply_status(filter.apply(Payment.all))
      direction = params[:direction] == "asc" ? "asc" : "desc"
      csv_data = ExportSummaryCsv.call(base_scope, direction: direction)

      send_data csv_data,
                filename: "ventas-resumen-declaracion-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.csv",
                type: "text/csv"
    end

    private

    def send_filtered_csv(exporter)
      filter = VentasFilter.new(params)
      base_scope = filter.apply_status(filter.apply(Payment.all))
      direction = params[:direction] == "asc" ? "asc" : "desc"
      payments = base_scope.order(created_at: direction.to_sym)
      csv_data = exporter.call(payments)

      send_data csv_data,
                filename: "ventas-export-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.csv",
                type: "text/csv"
    end

    def page_param(name)
      raw = params[name].presence || params[:page]
      [ raw.to_i, 1 ].max
    end
  end
end
