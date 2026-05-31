# frozen_string_literal: true

module Admin
  # [REQ-FIT-ADMIN-001] Group succeeded payments by CR day + method for Hacienda exports.
  class HaciendaSummaryRows
    CR_ZONE = "America/Costa_Rica"

    def self.net_collected(payment)
      payment.total_amount.to_f.positive? ? payment.total_amount.to_f : payment.amount.to_f
    end

    def self.succeeded_groups(payments, currency:)
      payments
        .where(status: "succeeded", currency: currency)
        .group_by do |payment|
          date_str = payment.created_at.in_time_zone(CR_ZONE).to_date.to_s
          [ date_str, payment.payment_method ]
        end
    end

    def self.sorted_keys(grouped, direction: "desc")
      keys = grouped.keys.sort_by { |k| [ k[0], k[1] ] }
      direction == "desc" ? keys.reverse : keys
    end

    def self.row_values(date_str, currency, payment_method, group)
      [
        date_str,
        currency.to_s.upcase,
        PaymentDisplayLabels.payment_method_label(payment_method),
        group.size,
        group.sum { |p| p.list_price.to_f }.round(2),
        group.sum { |p| p.discount_amount.to_f }.round(2),
        group.sum { |p| p.subtotal.to_f }.round(2),
        group.sum { |p| p.tax_amount.to_f }.round(2),
        group.sum { |p| net_collected(p) }.round(2)
      ]
    end

    def self.totals_row(sorted_keys, grouped, currency)
      [
        "TOTAL #{currency.to_s.upcase}",
        currency.to_s.upcase,
        "—",
        sorted_keys.sum { |k| grouped.fetch(k).size },
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| p.list_price.to_f } }.round(2),
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| p.discount_amount.to_f } }.round(2),
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| p.subtotal.to_f } }.round(2),
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| p.tax_amount.to_f } }.round(2),
        sorted_keys.sum { |k| grouped.fetch(k).sum { |p| net_collected(p) } }.round(2)
      ]
    end
  end
end
