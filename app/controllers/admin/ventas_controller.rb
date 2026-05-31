# frozen_string_literal: true

module Admin
  class VentasController < Admin::BaseController
    def index
      base_scope = Payment.all

      # Apply date filters
      if params[:start_date].present?
        begin
          start_time = Time.zone.parse(params[:start_date]).beginning_of_day
          base_scope = base_scope.where("created_at >= ?", start_time)
        rescue ArgumentError
          # Ignore invalid date formats
        end
      end

      if params[:end_date].present?
        begin
          end_time = Time.zone.parse(params[:end_date]).end_of_day
          base_scope = base_scope.where("created_at <= ?", end_time)
        rescue ArgumentError
          # Ignore invalid date formats
        end
      end

      # Apply payment method filter
      if params[:payment_method].present?
        base_scope = base_scope.where(payment_method: params[:payment_method])
      end

      # Apply search
      if params[:search].present?
        q = "%#{params[:search]}%"
        base_scope = base_scope.where(
          "purchaser_name ILIKE :q OR purchaser_email ILIKE :q OR purchase_reference ILIKE :q OR sinpe_transfer_identification ILIKE :q",
          q: q
        )
      end

      # Compute metrics on the filtered base scope (excluding status filter)
      @total_revenue_crc = base_scope.where(status: "succeeded", currency: "crc").sum("COALESCE(NULLIF(total_amount, 0), amount)")
      @total_revenue_usd = base_scope.where(status: "succeeded", currency: "usd").sum("COALESCE(NULLIF(total_amount, 0), amount)")
      @succeeded_count = base_scope.where(status: "succeeded").count
      @failed_count = base_scope.where(status: "failed").count
      @pending_count = base_scope.where(status: "pending").count

      # Apply status filter for listing
      @payments_scope = base_scope
      if params[:status].present?
        @payments_scope = @payments_scope.where(status: params[:status])
      end

      # Pagination
      @page = [params[:page].to_i, 1].max
      per_page = 20
      @total_count = @payments_scope.count
      @total_pages = (@total_count.to_f / per_page).ceil
      @payments = @payments_scope.order(created_at: :desc).limit(per_page).offset((@page - 1) * per_page)
    end

    def export
      base_scope = Payment.all

      if params[:start_date].present?
        begin
          start_time = Time.zone.parse(params[:start_date]).beginning_of_day
          base_scope = base_scope.where("created_at >= ?", start_time)
        rescue ArgumentError
        end
      end

      if params[:end_date].present?
        begin
          end_time = Time.zone.parse(params[:end_date]).end_of_day
          base_scope = base_scope.where("created_at <= ?", end_time)
        rescue ArgumentError
        end
      end

      if params[:payment_method].present?
        base_scope = base_scope.where(payment_method: params[:payment_method])
      end

      if params[:search].present?
        q = "%#{params[:search]}%"
        base_scope = base_scope.where(
          "purchaser_name ILIKE :q OR purchaser_email ILIKE :q OR purchase_reference ILIKE :q OR sinpe_transfer_identification ILIKE :q",
          q: q
        )
      end

      if params[:status].present?
        base_scope = base_scope.where(status: params[:status])
      end

      payments = base_scope.order(created_at: :desc)
      csv_data = ExportPaymentsCsv.call(payments)

      send_data csv_data,
                filename: "ventas-export-#{Time.current.strftime('%Y-%m-%d-%H%M%S')}.csv",
                type: "text/csv"
    end
  end
end
